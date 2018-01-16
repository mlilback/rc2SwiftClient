//
//  AppLogger.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import ClientCore
import os
import SwiftyUserDefaults

private extension DefaultsKeys {
	static let globalLogVersion = DefaultsKey<Int>("currentSupportDataVersion")
	static let logCategoryLevels = DefaultsKey<[String: Int]>("logLevels")
}

class AppLogger: NSObject {
	let logBuffer = NSTextStorage()
	let config = Rc2LogConfig()
	private(set) var globalLevelMenu: NSMenu?
	private var logWindowController: NSWindowController?
	
	func start(globalLevelMenu: NSMenu?) {
		self.globalLevelMenu = globalLevelMenu
		self.globalLevelMenu?.delegate = self
		let fmtString = HTMLString(text: "(%level) <color hex=\"006600FF\">[(%category)]</color> [(%date)] [(%function):(%filename):(%line)] (%message)")
		#if DEBUG
			let attrFmtString = HTMLString(text: "(%level) <color hex=\"006600FF\">[(%category)]</color> [(%date)] <color hex=\"AF2638FF\">[(%function):(%filename):(%line)]</color> (%message)")
		#else
			let attrFmtString = HTMLString(text: "(%level) <color hex=\"006600FF\">[(%category)]</color> [(%date)] (%message)")
		#endif
		let attrFormatter = TokenizedLogFormatter(config: config, formatString: attrFmtString.attributedString(), dateFormatter: config.dateFormatter)
		let plainFormatter = TokenizedLogFormatter(config: config, formatString: fmtString.attributedString(), dateFormatter: config.dateFormatter)
		let logger = Logger(config: config)
		logger.append(handler: StdErrHandler(config: config, formatter: plainFormatter))
		logger.append(handler: AttributedStringLogHandler(formatter: attrFormatter, output: logBuffer))
		config.categoryLevels[.session] = .debug
		config.categoryLevels[.app] = .debug
		// add on a file logger
		do {
			let logUrl = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("\(AppInfo.bundleIdentifier).log")
			if !FileManager.default.fileExists(atPath: logUrl.path) {
				try "".write(to: logUrl, atomically: true, encoding: .utf8)
			}
			guard let fh = try? FileHandle(forWritingTo: logUrl) else { throw GenericError("failed to create log file") }
			fh.seekToEndOfFile()
			logger.append(handler: FileHandleLogHandler(config: config, fileHandle: fh, formatter: plainFormatter))
		} catch {
			os_log("error opening log file: %{public}@", error.localizedDescription)
		}
		Log.enableLogging(logger)
	}
	
	func showLogWindow(_ sender: Any? = nil) {
		if nil == logWindowController {
			if #available(OSX 10.13, *) {
				logWindowController = NSStoryboard.main?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("LogWindowController")) as? NSWindowController
			} else {
				// Fallback on earlier versions
				let sboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
				logWindowController = sboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("LogWindowController")) as? NSWindowController
			}
			guard let logController = logWindowController?.contentViewController as? LogViewController else { fatalError() }
			logController.logTextView.layoutManager?.replaceTextStorage(logBuffer)
		}
		logWindowController?.window?.makeKeyAndOrderFront(sender)
	}
	
	@objc func adjustGlobalLogLevel(_ sender: Any?) {
		guard let item = sender as? NSMenuItem, item.parent?.submenu == globalLevelMenu
			else { Log.warn("action only callable from debug menu", .app); return }
		guard let newLevel = LogLevel(rawValue: item.tag)
			else { Log.warn("tag not convertable to log level", .app); return }
		Log.info("changing log level to \(newLevel)", .app)
		config.globalLevel = newLevel
	}
}

extension AppLogger: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		for anItem in globalLevelMenu!.items {
			guard let itemLevel = LogLevel(rawValue: anItem.tag) else { continue }
			anItem.state = config.globalLevel == itemLevel ? .on : .off
			anItem.target = self
			anItem.action = #selector(MacAppDelegate.adjustGlobalLogLevel(_:))
			anItem.isEnabled = itemLevel != config.globalLevel
		}
	}

}

// MARK: -
class Rc2LogConfig: LogConfiguration {
	let dateFormatter: DateFormatterProtocol
	var categoryLevels = [LogCategory: LogLevel]()
	var globalLevel: LogLevel = .warn { didSet {
			UserDefaults.standard[.globalLogVersion] = globalLevel.rawValue
		}}
	let levelDescriptions: [LogLevel: NSAttributedString]

	init() {
		let dformatter = DateFormatter()
		dformatter.locale = Locale(identifier: "en_US_POSIX")
		dformatter.dateFormat = "HH:mm:ss.SSS"
		dateFormatter = dformatter
		levelDescriptions = [
			.debug: NSAttributedString(string: "🐞"),
			.error: NSAttributedString(string: "🛑"),
			.warn: NSAttributedString(string: "⚠️"),
			.info: NSAttributedString(string: "ℹ️"),
			.enter: NSAttributedString(string: "→"),
			.exit: NSAttributedString(string: "←")
		]
		let defaults = UserDefaults.standard
		if let savedGlobal = LogLevel(rawValue: defaults[.globalLogVersion]) {
			globalLevel = savedGlobal
		}
	}
	
	func loggingEnabled(level: LogLevel, category: LogCategory) -> Bool {
		if let catLevel = categoryLevels[category] { return level <= catLevel }
		return level <= globalLevel
	}
	
	func description(logLevel: LogLevel) -> NSAttributedString {
		if let desc = levelDescriptions[logLevel] { return desc }
		return NSAttributedString(string: logLevel.description)
	}
	
}

