//
//  RevenueCatAppStoreProvider.swift
//  I_EFIS
//
//  Created by Farid Dahiri on 26.07.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import AWLogger
import Combine
import Foundation
import RevenueCat
import StoreKit
import UIKit

@MainActor
final class RevenueCatAppStoreProvider: AppStoreProviding {
    var lastKnownSubscriptionStatus: SubscriptionStatus {
        _subscriptionStatusPublisher.value
    }
    
    let logger: Logging
    var subscriptionStatusPublisher: AnyPublisher<SubscriptionStatus, Never> {
        _subscriptionStatusPublisher.eraseToAnyPublisher()
    }
    private let _subscriptionStatusPublisher = CurrentValueSubject<SubscriptionStatus, Never>(.unknown)
    private var monitoringTask: Task<Void, Never>?
    
    private var products: [Package] = []
    
    init(logger: Logging) {
        self.logger = logger
        startMonitoringSubscriptionStatus()
    }
    
    deinit {
        monitoringTask?.cancel()
    }
    
    func fetchProducts() async throws -> [EFProduct] {
        let offerings = try await Purchases.shared.offerings()
        guard let availablePackages = offerings.current?.availablePackages else {
            return []
        }
        self.products = availablePackages

        return try await withThrowingTaskGroup(of: EFProduct.self) { group in
            for package in availablePackages {
                group.addTask {
                    let product = package.storeProduct
                    let hasUsedTrial = await self.hasUsedFreeTrial(for: product.productIdentifier)

                    let displayPrice: String
                    if !hasUsedTrial,
                       let intro = product.introductoryDiscount,
                       intro.paymentMode == .freeTrial {
                        
                        let unit = intro.subscriptionPeriod.unit
                        let value = intro.subscriptionPeriod.value
                        let duration: String
                        switch unit {
                        case .day: duration = "\(value)-day"
                        case .week: duration = "\(value)-week"
                        case .month: duration = "\(value)-month"
                        case .year: duration = "\(value)-year"
                        @unknown default: duration = "\(value)"
                        }
                        
                        displayPrice = "Free \(duration) trial, then \(product.localizedPriceString)"
                    } else {
                        displayPrice = product.localizedPriceString
                    }

                    return EFProduct(
                        id: package.identifier,
                        displayName: product.localizedTitle,
                        displayPrice: displayPrice,
                        details: product.localizedDescription,
                        billingRecurrence: product.subscriptionPeriod?.debugDescription ?? "Unknown"
                    )
                }
            }

            var results: [EFProduct] = []
            for try await efProduct in group {
                results.append(efProduct)
            }

            return results
        }
    }
    
    func purchaseSubscription() async throws -> EFPurchaseTransaction? {
        guard let package = products.first else { return nil }
        let result = try await Purchases.shared.purchase(package: package)
        await updateCustomerInfo()
        if let productIdentifier = result.transaction?.productIdentifier {
            return EFPurchaseTransaction(
                productIdentifier: productIdentifier,
                price: package.storeProduct.priceDecimalNumber
            )
        } else {
            throw StoreKitError.invalidTransacation
        }
    }
    
    func restorePurchases() async throws {
        _ = try await Purchases.shared.restorePurchases()
        await updateCustomerInfo()
    }
    
    func showManageSubscriptions() {
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
    
    func setUserId(_ userId: String) async {
        do {
            _ = try await Purchases.shared.logIn(userId)
            await updateCustomerInfo()
        } catch {
            logger.error("RevenueCat logIn failed for userId \(userId): \(error)")
        }
    }
    
    func configure(withAPIKey apiKey: String) {
        Purchases.configure(withAPIKey: apiKey)
    }
    
    private func startMonitoringSubscriptionStatus() {
        monitoringTask = Task {
            while !Task.isCancelled {
                await updateCustomerInfo()
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Sleep for 60 seconds
            }
        }
    }
    
    private func hasUsedFreeTrial(for productId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: [productId]) { eligibilityDict in
                let usedTrial: Bool
                if let status = eligibilityDict[productId]?.status {
                    usedTrial = (status != .eligible)
                } else {
                    usedTrial = true // default to "used" if undetermined
                }
                continuation.resume(returning: usedTrial)
            }
        }
    }
    
    private func updateCustomerInfo() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            if customerInfo.entitlements.active.isEmpty {
                _subscriptionStatusPublisher.send(.inactive)
            } else if let entitlement = customerInfo.entitlements.all.values.first,
                      let expiration = entitlement.expirationDate {
                _subscriptionStatusPublisher.send(.active(expiration))
            } else {
                _subscriptionStatusPublisher.send(.unknown)
            }
        } catch {
            _subscriptionStatusPublisher.send(.unknown)
        }
    }
}
