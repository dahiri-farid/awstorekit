//
//  File.swift
//  AWStoreKit
//
//  Created by Farid Dahiri on 31.07.2025.
//

import AWLogger
import Foundation

extension Logging {
    func verbose(
        _ message: Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.verbose(message, file: file, function: function, line: line)
    }
    func debug(
        _ message: Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.debug(message, file: file, function: function, line: line)
    }
    func info(
        _ message: Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.info(message, file: file, function: function, line: line)
    }
    func warning(
        _ message: Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.warning(message, file: file, function: function, line: line)
    }
    func error(
        _ message: Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.error(message, file: file, function: function, line: line)
    }
}


