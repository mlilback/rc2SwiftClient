//
//  AppLoggerTests.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
@testable import MacClient
@testable import MJLLogger

// swiftlint:disable all

class AppLoggerTests: XCTestCase {
	func testLastJsonEntry() throws {
		let fm = FileManager()
		let srcFile = Bundle(for: type(of: self)).url(forResource: "sampleLog", withExtension: "json")!
		let tmpUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try! fm.copyItem(at: srcFile, to: tmpUrl)
		defer { try! fm.removeItem(at: tmpUrl) }
		
		let appLogger = AppLogger(jsonLogFileURL: tmpUrl)
		let lastEntryStr = appLogger.jsonLogFromLastLaunch()
		XCTAssertNotNil(lastEntryStr)
		let lines = lastEntryStr!.components(separatedBy: "\n")
		XCTAssertEqual(lines.count, 3)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let entries = try lines.map { try decoder.decode(LogEntry.self, from: $0.data(using: .utf8)!) }
		XCTAssertEqual(entries[1].category, LogCategory("docker"))
		XCTAssertEqual(entries[2].function, "pullIsNecessary()")
	}
}
