//
//  AppStoreProviderMock.swift
//  iEFIS Pro Beta
//
//  Created by Farid Dahiri on 02.03.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import AWLogger
import Combine
import Foundation

public class AppStoreProviderMock: AppStoreProviding {
    
    let logger: Logging
    
    public var subscriptionStatusPublisher: AnyPublisher<SubscriptionStatus, Never> {
        _subscriptionStatusPublisher.eraseToAnyPublisher()
    }
    private let _subscriptionStatusPublisher: CurrentValueSubject<SubscriptionStatus, Never> = .init(.active(Date()))
    
    init(logger: Logging) {
        self.logger = logger
    }
    
    public func fetchProducts() async throws -> [EFProduct] {
        []
    }
    
    public func purchaseSubscription() async throws -> EFPurchaseTransaction? {
        throw NSError(domain: "AppStoreProviderMock", code: 0, userInfo: nil)
    }
    
    public func showManageSubscriptions() {}
    
    public func restorePurchases() async throws {}
    
    public func setUserId(_ userId: String) async {}
    
    public func configure(withAPIKey apiKey: String) {}
}
