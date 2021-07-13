//
//  LoggingTestCase.swift
//  FetchRequests-iOSTests
//
//  Created by Adam Lickel on 9/21/19.
//  Copyright © 2019 Speramus Inc. All rights reserved.
//

import XCTest
@testable import FetchRequests

class LoggingTestCase: XCTestCase {
    func testLogging() {
        CWLogVerbose("Verbose")
        CWLogDebug("Debug")
        CWLogInfo("Info")
        CWLogWarning("Warning")
        CWLogError("Error")
    }
}
