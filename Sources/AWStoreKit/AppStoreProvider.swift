//
//  AppStoreProvider.swift
//  I_EFIS
//
//  Created by Farid Dahiri on 01.01.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import AWLogger
import Combine
import Foundation
import StoreKit

@MainActor
public class AppStoreProvider: AppStoreProviding {
    let logger: Logging
    
    public let subscriptionStatusPublisher: CurrentValueSubject<SubscriptionStatus, Never> = CurrentValueSubject(.inactive)
    private var cancellables: Set<AnyCancellable> = []
    
    private let subscriptionProvider: SubscriptionProvider
    
    private var task: Task<Void, Error>?
    
    init(logger: Logging) {
        self.logger = logger
        self.subscriptionProvider = SubscriptionProvider(logger: logger)
        subscriptionProvider.subscriptionGroupStatusPublisher.sink { [unowned self] status in
            self.logger.info("subscription status changed \(String(describing: status))")
            self.subscriptionStatusPublisher.send(self.convertStatus(status))
        }.store(in: &cancellables)
        
        task = monitorSubscriptionStatus()
    }

    // MARK: - MONITOR SUBSCRIPTION STATUS

    private func monitorSubscriptionStatus() -> Task<Void, Error> {
        return subscriptionProvider.listenForTransactions()
    }
    
    // MARK: - SHOW MANAGE SUBSCRIPTIONS
    
    public func showManageSubscriptions() {
        logger.info("show manage subscirptions")
        subscriptionProvider.showManageSubscriptions()
    }
    
    // MARK: - RESTORE PURCHASES
    
    public func restorePurchases() async throws {
        try await subscriptionProvider.restorePurchases()
    }

    // MARK: - PURCHASE A SUBSCRIPTION

    public func purchaseSubscription() async throws -> EFPurchaseTransaction? {
        logger.info("purchase subscription \(subscriptionProvider.productId)")
        guard let product = try await fetchProduct(id: subscriptionProvider.productId) else {
            logger.error("error purchasing subscription \(subscriptionProvider.productId)")
            throw NSError(domain: "AppStoreProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Product not found."])
        }
        guard let transaction = try await subscriptionProvider.purchase(product) else {
            logger.info("transaction cancelled")
            return nil
        }
        let price = transaction.price ?? 0.0
        logger.info("purchased subscription price \(price)")
        return EFPurchaseTransaction(productIdentifier: product.id, price: price as NSDecimalNumber)
    }
    
    // MARK: - FETCH PRODUCTS
    
    public func fetchProducts() async throws -> [EFProduct] {
        await subscriptionProvider.requestProducts()
        logger.info("fetched products \(subscriptionProvider.subscriptionsPublisher.value)")
        return try await withThrowingTaskGroup(of: EFProduct.self) { group in
            for product in subscriptionProvider.subscriptionsPublisher.value {
                group.addTask {
                    let usedTrial = await self.subscriptionProvider.hasUsedFreeTrial(for: product)
                    let displayPrice = await usedTrial
                        ? product.displayPrice
                        : self.formatPriceWithTrial(for: product)
                    
                    return EFProduct(
                        id: product.id,
                        displayName: product.displayName,
                        displayPrice: displayPrice,
                        details: product.description,
                        billingRecurrence: product.type.rawValue
                    )
                }
            }

            var result: [EFProduct] = []
            for try await item in group {
                result.append(item)
            }
            return result
        }
    }
    
    public func setUserId(_ userId: String) async {}
    
    public func configure(withAPIKey apiKey: String) {}
    
    private func fetchProduct(id: String) async throws -> Product? {
        await subscriptionProvider.requestProducts()
        let products = subscriptionProvider.subscriptionsPublisher.value
        logger.info("fetched products \(subscriptionProvider.subscriptionsPublisher.value)")
        guard let product = products.first(where: { $0.id == id }) else {
            throw NSError(domain: "AppStoreProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Product not found."])
        }
        return product
    }
    
    // MARK: - CHECK SUBSCRIPTION STATUS
    
    private func convertStatus(_ status: Product.SubscriptionInfo.Status?) -> SubscriptionStatus {
        guard let status else {
            logger.info("subscription status not available")
            return .inactive
        }
        guard case .verified(_) = status.renewalInfo,
              case .verified(let transaction) = status.transaction else {
            logger.warning("could not verify your subscription status")
            return .inactive
        }

        let convertedStatus: SubscriptionStatus = switch status.state {
        case .subscribed:
            if let expirationDate = transaction.expirationDate {
                SubscriptionStatus.active(expirationDate)
            } else {
                SubscriptionStatus.inactive
            }
        case .expired:
            SubscriptionStatus.expired
        case  .revoked:
            SubscriptionStatus.revoked
        case .inGracePeriod:
            SubscriptionStatus.inGracePeriod
        case .inBillingRetryPeriod:
            SubscriptionStatus.inBillingRetryPeriod
        default:
            SubscriptionStatus.inactive
        }
        
        logger.info("subscription status \(status) -> converted status \(convertedStatus)")
        
        return convertedStatus
    }
    
    // MARK: - HAS USED TRIAL
    
    func hasUsedFreeTrial() async -> Bool {
        guard let product = try? await fetchProduct(id: subscriptionProvider.productId) else {
            return true
        }
        return await subscriptionProvider.hasUsedFreeTrial(for: product)
    }
    
    // MARK: - UTILS
    
    func formatPriceWithTrial(for product: Product) -> String {
        if let offer = product.subscription?.introductoryOffer,
           offer.paymentMode == .freeTrial {
            let unit = offer.period.unit
            let value = offer.period.value
            
            let durationString: String
            switch unit {
            case .day:
                durationString = "\(value)-day"
            case .week:
                durationString = "\(value)-week"
            case .month:
                durationString = "\(value)-month"
            case .year:
                durationString = "\(value)-year"
            @unknown default:
                durationString = "\(value)"
            }
            
            return "Free \(durationString) trial, then \(product.displayPrice)"
        }
        
        return product.displayPrice
    }
}

