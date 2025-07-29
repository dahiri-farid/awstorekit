//
//  Store.swift
//  iEFIS Pro Beta
//
//  Created by Farid Dahiri on 02.03.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import Combine
import Foundation
import StoreKit

public typealias Transaction = StoreKit.Transaction
public typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
public typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

public enum StoreError: Error {
    case failedVerification
}

// Define the app's subscription entitlements by level of service, with the highest level of service first.
// The numerical-level value matches the subscription's level that you configure in
// the StoreKit configuration file or App Store Connect.
public enum ServiceEntitlement: Int, Comparable {
    case notEntitled = 0
    
    case pro = 1
    case premium = 2
    case standard = 3
    
    init?(for product: Product) {
        // The product must be a subscription to have service entitlements.
        guard let subscription = product.subscription else {
            return nil
        }
        self.init(rawValue: subscription.groupLevel)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        // Subscription-group levels are in descending order.
        return lhs.rawValue > rhs.rawValue
    }
}

@MainActor
public class SubscriptionProvider {
    let logger: Logging
    
    let subscriptionsPublisher: CurrentValueSubject<[Product], Never> = CurrentValueSubject([])
    let purchasedSubscriptionsPublisher: CurrentValueSubject<[Product], Never> = CurrentValueSubject([])
    let subscriptionGroupStatusPublisher: CurrentValueSubject<Product.SubscriptionInfo.Status?, Never> = CurrentValueSubject(nil)
    
    var updateListenerTask: Task<Void, Error>? = nil
    
    let productId: String

    private let productIdToTitle: [String: String]
    
    private var monitoringTask: Task<Void, Never>?

    public init(logger: Logging) {
        self.logger = logger
        productIdToTitle = SubscriptionProvider.loadProductData()
        
        guard let productId = productIdToTitle.keys.first else {
            preconditionFailure("No products defined")
        }
        self.productId = productId
        
        // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()
        
        Task {
            // During store initialization, request products from the App Store.
            await requestProducts()
            
            // Deliver products that the customer purchases.
            await updateCustomerProductStatus()
        }
        startMonitoringSubscriptionStatus()
    }

    deinit {
        updateListenerTask?.cancel()
        monitoringTask?.cancel()
    }
    
    static func loadProductData() -> [String: String] {
        guard let path = Bundle.main.path(forResource: "Products", ofType: "plist"),
              let plist = FileManager.default.contents(atPath: path),
              let data = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: String] else {
            return [:]
        }
        return data
    }

    public func listenForTransactions() -> Task<Void, Error> {
        logger.info("listening for transactions")
        return Task {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                logger.info("transaction update: \(result)")
                do {
                    let transaction = try self.checkVerified(result)

                    // Deliver products to the user.
                    await self.updateCustomerProductStatus()

                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    logger.error("transaction failed verification \(error)")
                }
            }
        }
    }

    @MainActor
    public func requestProducts() async {
        do {
            // Request products from the App Store using the identifiers that the `Products.plist` file defines.
            let storeProducts = try await Product.products(for: productIdToTitle.keys)

            var newSubscriptions: [Product] = []

            // Filter the products into categories based on their type.
            for product in storeProducts {
                switch product.type {
                case .autoRenewable:
                    newSubscriptions.append(product)
                default:
                    // Ignore this product.
                    logger.error("unknown product: \(product)")
                }
            }

            subscriptionsPublisher.send(newSubscriptions)
        } catch {
            logger.error("failed product request from the App Store server: \(error)")
        }
    }

    public func purchase(_ product: Product) async throws -> Transaction? {
        // Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()
        logger.info("purhase result: \(result)")
        switch result {
        case .success(let verification):
            // Check whether the transaction is verified. If it isn't,
            // this function rethrows the verification error.
            let transaction = try checkVerified(verification)

            // The transaction is verified. Deliver content to the user.
            await updateCustomerProductStatus()

            // Always finish a transaction.
            await transaction.finish()

            return transaction
        case .userCancelled, .pending:
            return nil
        default:
            return nil
        }
    }

    private func isPurchased(_ product: Product) async throws -> Bool {
        // Determine whether the user purchases a given product.
        switch product.type {
        case .autoRenewable:
            return purchasedSubscriptionsPublisher.value.contains(product)
        default:
            return false
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            logger.error("unverified transaction")
            throw StoreError.failedVerification
        case .verified(let safe):
            // The result is verified. Return the unwrapped value.
            return safe
        }
    }

    private func updateCustomerProductStatus() async {
        var purchasedSubscriptions: [Product] = []
        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                // Check whether the transaction is verified. If it isn’t, catch `failedVerification` error.
                let transaction = try checkVerified(result)

                // Check the `productType` of the transaction and get the corresponding product from the store.
                switch transaction.productType {
                case .autoRenewable:
                    if let subscription = subscriptionsPublisher.value.first(where: { $0.id == transaction.productID }) {
                        purchasedSubscriptions.append(subscription)
                    }
                default:
                    break
                }
            } catch {
                logger.error("error verifying transaction: \(error)")
            }
        }

        // Update the store information with auto-renewable subscription products.
        self.purchasedSubscriptionsPublisher.send(purchasedSubscriptions)

        // Check the `subscriptionGroupStatus` to learn the auto-renewable subscription state to determine whether the customer
        // is new (never subscribed), active, or inactive (expired subscription).
        // This app has only one subscription group, so products in the subscriptions array all belong to the same group.
        // Customers can be subscribed to only one product in the subscription group.
        // The statuses that `product.subscription.status` returns apply to the entire subscription group.
        let subscriptionGroupStatus = try? await subscriptionsPublisher.value.first?.subscription?.status.max { lhs, rhs in
            // There may be multiple statuses for different family members, because this app supports Family Sharing.
            // The subscriber is entitled to service for the status with the highest level of service.
            let lhsEntitlement = entitlement(for: lhs)
            let rhsEntitlement = entitlement(for: rhs)
            return lhsEntitlement < rhsEntitlement
        }
        subscriptionGroupStatusPublisher.send(subscriptionGroupStatus)
    }

    // Get a subscription's level of service using the product ID.
    private func entitlement(for status: Product.SubscriptionInfo.Status) -> ServiceEntitlement {
        // If the status is expired, then the customer is not entitled.
        if status.state == .expired || status.state == .revoked {
            return .notEntitled
        }
        // Get the product associated with the subscription status.
        let productID = status.transaction.unsafePayloadValue.productID
        guard let product = subscriptionsPublisher.value.first(where: { $0.id == productID }) else {
            return .notEntitled
        }
        // Finally, get the corresponding entitlement for this product.
        return ServiceEntitlement(for: product) ?? .notEntitled
    }
    
    public func hasUsedFreeTrial(for product: Product) async -> Bool {
        guard let subscription = product.subscription else { return true }

        let isEligible = await subscription.isEligibleForIntroOffer
        return !isEligible
    }
    
    // MARK: - RESTORE PURCHASES
    public func restorePurchases() async throws {
        logger.info("appstore sync began")
        try await AppStore.sync()
        logger.info("appstore sync ended")
    }
    
    // MARK: - SHOW MANAGE SUBSCRIPTIONS
    public func showManageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            logger.error("no UIWindowScene found")
            return
        }
        
        Task {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                logger.error("failed to show manage subscriptions page: \(error)")
            }
        }
    }
    
    public func startMonitoringSubscriptionStatus() {
        monitoringTask = Task {
            while !Task.isCancelled {
                await updateCustomerProductStatus()
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Sleep for 60 seconds
            }
        }
    }
}

