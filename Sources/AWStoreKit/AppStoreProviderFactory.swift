//
//  AppStoreProviderFactory.swift
//  iEFIS Pro Beta
//
//  Created by Farid Dahiri on 02.03.2025.
//  Copyright © 2025 FU-airWORK. All rights reserved.
//

import AWLogger
import Foundation

@MainActor
public class AppStoreProviderFactory: Sendable {
    public enum ProviderType {
        case mock
        case revenuecat
        case storekit
    }
    public static func make(providerType: ProviderType, logger: Logging) -> AppStoreProviding {
        switch providerType {
        case .mock:
            AppStoreProviderMock(logger: logger)
        case .revenuecat:
            RevenueCatAppStoreProvider(logger: logger)
        case .storekit:
            AppStoreProvider(logger: logger)
        }
    }
}
