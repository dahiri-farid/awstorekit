//
//  AppStoreProviding.swift
//  iEFIS Pro Beta
//
//  Created by Farid Dahiri on 02.03.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import Combine
import Foundation


@MainActor
public protocol AppStoreProviding {
    var subscriptionStatusPublisher: AnyPublisher<SubscriptionStatus, Never> { get }
    
    func fetchProducts() async throws -> [EFProduct]
    func purchaseSubscription() async throws -> EFPurchaseTransaction?
    func showManageSubscriptions()
    func restorePurchases() async throws
    func setUserId(_ userId: String) async
    func configure(withAPIKey apiKey: String)
}

public enum SubscriptionStatus: Equatable {
    case active(Date)
    case inactive
    case expired
    case revoked
    case inGracePeriod
    case inBillingRetryPeriod
    case unknown
}

public struct EFPurchaseTransaction {
    public let productIdentifier: String
    public let price: NSDecimalNumber
    
    public init(productIdentifier: String, price: NSDecimalNumber) {
        self.productIdentifier = productIdentifier
        self.price = price
    }
}

public struct EFProduct: Sendable {
    public let id: String
    public let displayName: String
    public let displayPrice: String
    public let details: String
    public let billingRecurrence: String
    
    public init(id: String, displayName: String, displayPrice: String, details: String, billingRecurrence: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.details = details
        self.billingRecurrence = billingRecurrence
    }
}

enum StoreKitError: Error {
    case invalidTransacation
}
