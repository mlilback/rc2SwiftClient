//
//  AppLogger.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import Rc2Common
import os
import SwiftyUserDefaults

fileprivate extension DefaultsKeys {
	static let globalLogVersion = DefaultsKey<Int>("currentSupportDataVersion", defaultValue: 0)
	static let logCategoryLevels = DefaultsKey<[String: Any]>("logLevels", defaultValue: [:])
}

// MARK: -
/// internal enum mapped to LogLevel for the limited set of options we offer in UI. Also allows default value.
private enum OtherLogLevel: Int, CaseIterable {
	case `default` = 0
	case error = 2
	case warn = 3
	case info = 5
	case debug = 6

	/// return appropriate OtherLogLevel for a LogLevel
	static func from(_ level: MJLLogLevel) -> OtherLogLevel {
		if let llevel = OtherLogLevel(rawValue: level.rawValue) { return llevel }
		if level == .notice { return .info }
		if level == .trace { return .debug }
		return .default
	}

	/// sets a menu title for this OtherLogLevel with appropriate formatting
	func setTitle(menuItem: NSMenuItem) {
		switch self {
		case .default:
			let baseFont = NSFont.menuFont(ofSize: 0)
			let fontDesc = NSFont(descriptor: baseFont.fontDescriptor, size: baseFont.pointSize)!
				.fontDescriptor
				.withSymbolicTraits(.italic)
			let font = NSFont(descriptor: fontDesc, size: baseFont.pointSize)!
			menuItem.attributedTitle = NSAttributedString(string: "default", attributes: [NSAttributedString.Key.font: font])
		case .error:
			menuItem.title = "error"
		case .warn:
			menuItem.title = "warn"
		case .info:
			menuItem.title = "info"
		case .debug:
			menuItem.title = "debug"
		}
	}

	/// returns the represented LogLevel, or nil for default
	var logLevel: MJLLogLevel? { return MJLLogLevel(rawValue: rawValue) }
}

// MARK: -
class AppLogger: NSObject {
	// MARK: constants
	let fmtString = HTMLString(text: "(%level) <color hex=\"006600FF\">[(%category)]</color> [(%date)] [(%function):(%filename):(%line)] (%message)")
	#if DEBUG
	let attrFmtString = HTMLString(text: "(%level) <color hex=\"006600FF\">[(%category)]</color> [(%date)] <color hex=\"AF2638FF\">[(%function):(%filename):(%line)]</color> (%message)")
	#else
	let attrFmtString = HTMLString(text: "(%level) <color hex=\"006600FF\">[(%category)]</color> [(%date)] (%message)")
	#endif

	// MARK: properties
	let logBuffer = NSTextStorage()
	let config = Rc2LogConfig()
	private var globalLevelMenu: NSMenu?
	private var categoryMenuItem: NSMenuItem?
	private var logWindowController: NSWindowController?
	private var menu2Category: [NSMenu: LogCategory] = [:]
	private var jsonOutputHandler: FileHandleLogHandler?
	private var attrOutputHandler: AttributedStringLogHandler?
	private let jsonOutputURL: URL?
	// MARK: methods

	/// Creates an AppLogger
	///
	/// - Parameter jsonLogFileURL: The log file to use. For dependency injection. Defaults to ~/Library/Logs/BundleIdentifier.log
	init(jsonLogFileURL: URL? = nil) {
		do {
			if let jsonURL = jsonLogFileURL {
				jsonOutputURL = jsonURL
			} else {
				jsonOutputURL = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("\(AppInfo.bundleIdentifier).log")
			}
		} catch {
			os_log("Failed to resolve URL for jsonLog: %{public}@", error.localizedDescription)
			jsonOutputURL = nil
		}
		super.init()
	}

	/// starts/configures logging
	func start() {
		guard Log.logger == nil else { fatalError("logging already enabled") }
		let logger = MJLLogger(config: config)

		let plainFormatter = TokenizedLogFormatter(config: config, formatString: fmtString.attributedString(), dateFormatter: config.dateFormatter)
		logger.append(handler: StdErrHandler(config: config, formatter: plainFormatter))

		let attrFormatter = TokenizedLogFormatter(config: config, formatString: attrFmtString.attributedString(), dateFormatter: config.dateFormatter)
		attrOutputHandler = AttributedStringLogHandler(formatter: attrFormatter, output: logBuffer)
		logger.append(handler: attrOutputHandler!)

		addJsonLogger(logger: logger)

		Log.enableLogging(logger)
		logger.logApplicationStart()
	}

	/// installs UI in menu after specified menu item
	func installLoggingUI(addMenusAfter: NSMenuItem?) {
		// create menu infrastructure
		let menu = NSMenu(title: "Global Log Level")
		globalLevelMenu = menu
		categoryMenuItem = NSMenuItem(title: "Log Categories", action: nil, keyEquivalent: "")
		categoryMenuItem?.submenu = NSMenu(title: "Log Categories")
		globalLevelMenu?.delegate = self
		categoryMenuItem?.submenu?.delegate = self
		for aLevel in [MJLLogLevel.error, .warn, .info, .debug] {
			let mitem = menuItem(for: OtherLogLevel.from(aLevel))
			mitem.action = #selector(AppLogger.adjustGlobalLogLevel(_:))
			menu.addItem(mitem)
		}
		// add UI for logging options
		guard let baseItem = addMenusAfter, let parentMenu = baseItem.menu else { return }
		let globalItem = NSMenuItem(title: "Global Log Level", action: nil, keyEquivalent: "")
		globalItem.submenu = globalLevelMenu
		parentMenu.addItem(globalItem)
		parentMenu.addItem(categoryMenuItem!)
		let resetItem = NSMenuItem(title: "Reset All Categories", action: #selector(AppLogger.resetAllCategoriesToDefault(_:)), keyEquivalent: "")
		resetItem.target = self
		parentMenu.addItem(resetItem)
		for aCategory in LogCategory.allRc2Categories {
			let catMenu = menuItem(for: aCategory)
			menu2Category[catMenu.submenu!] = aCategory
			categoryMenuItem?.submenu?.addItem(catMenu)
		}
	}

	/// resets all log destinations
	func resetLogs() {
		logBuffer.replaceCharacters(in: logBuffer.string.fullNSRange, with: "")
		guard let logger = Log.logger else { return }
		if let jsonH = jsonOutputHandler {
			logger.remove(handler: jsonH)
		}
		if let logUrl = jsonOutputURL {
			do {
				if FileManager.default.fileExists(atPath: logUrl.path) {
					try FileManager.default.removeItem(at: logUrl)
				}
			} catch {
				os_log("failed to remove old jsonLog: %{public}@", error.localizedDescription)
			}
		}
		addJsonLogger(logger: logger)
	}
}

// MARK: - actions
extension AppLogger {
	/// displays (if not loaded) the log window and makes it key and front
	@objc func showLogWindow(_ sender: Any? = nil) {
		logWindow(show: true).makeKeyAndOrderFront(sender)
	}

	/// action for a log category's log level
	@objc func adjustLogLevel(_ sender: Any?) {
		guard let item = sender as? NSMenuItem
			else { Log.warn("action only callable from menu item", .app); return }
		guard let category = item.parent?.representedObject as? LogCategory
			else { Log.warn("failed to get category for log level"); return }
		guard let newLevel = MJLLogLevel(rawValue: item.tag) else {
			Log.debug("can't set \(category) to \(item.tag). setting to nil", .app)
			config.set(level: nil, forCategory: category)
			return
		}
		Log.info("setting \(category) to \(newLevel)", .app)
		config.set(level: newLevel, forCategory: category)
	}

	/// action for global log level menu item
	@objc func adjustGlobalLogLevel(_ sender: Any?) {
		guard let item = sender as? NSMenuItem, item.parent?.submenu == globalLevelMenu
			else { Log.warn("action only callable from debug menu", .app); return }
		guard let newLevel = MJLLogLevel(rawValue: item.tag)
			else { Log.warn("tag not convertable to log level", .app); return }
		Log.info("changing log level to \(newLevel)", .app)
		config.globalLevel = newLevel
	}

	/// removes all category log level overrides
	@objc func resetAllCategoriesToDefault(_ sender: Any?) {
		config.resetCategoryLevels()
	}
}

// MARK: - private methods
extension AppLogger {
	/// creates the log window if necessary and returns it
	func logWindow(show: Bool = true) -> NSWindow {
		if nil == logWindowController {
			if #available(OSX 10.13, *) {
				logWindowController = NSStoryboard.main?.instantiateController(withIdentifier: .logWindowController) as? NSWindowController
			} else {
				// Fallback on earlier versions
				let sboard = NSStoryboard(name: .mainBoard, bundle: nil)
				logWindowController = sboard.instantiateController(withIdentifier: .logWindowController) as? NSWindowController
			}
			guard let logController = logWindowController?.contentViewController as? LogViewController else { fatalError() }
			logController.logTextView.layoutManager?.replaceTextStorage(logBuffer)
			logController.logTextView.scrollToEndOfDocument(self)
			if let window = logWindowController?.window {
				window.isRestorable = true
				window.restorationClass = MacAppDelegate.self
				window.identifier = .logWindow
			}
		}
		return logWindowController!.window!
	}

	/// creates a menu item for category with an item for each possible OtherLogLevel
	private func menuItem(for category: LogCategory) -> NSMenuItem {
		let item = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
		let menu = NSMenu(title: category.rawValue)
		item.submenu = menu
		for aLevel in OtherLogLevel.allCases {
			menu.addItem(menuItem(for: aLevel))
		}
		menu.delegate = self
		menu.autoenablesItems = false
		item.representedObject = category
		return item
	}

	/// creates a menu item for a particular OtherLogLevel
	private func menuItem(for level: OtherLogLevel) -> NSMenuItem {
		let item = NSMenuItem(title: "", action: #selector(AppLogger.adjustLogLevel(_:)), keyEquivalent: "")
		level.setTitle(menuItem: item)
		item.tag = level.rawValue
		item.target = self
		item.action = #selector(AppLogger.adjustLogLevel(_:))
		return item
	}

	/// sets logger to save logs to a file in ~/Library/Logs/
	func addJsonLogger(logger: MJLLogger) {
		guard let logUrl = jsonOutputURL else { return }
		do {
			if !FileManager.default.fileExists(atPath: logUrl.path) {
				try "".write(to: logUrl, atomically: true, encoding: .utf8)
			}
			guard let fh = try? FileHandle(forWritingTo: logUrl) else { throw GenericError("failed to create log file") }
			fh.seekToEndOfFile()
			jsonOutputHandler = FileHandleLogHandler(config: config, fileHandle: fh, formatter: JSONLogFormatter(config: config), logEverything: true)
			logger.append(handler: jsonOutputHandler!)
		} catch {
			os_log("error opening log file: %{public}@", error.localizedDescription)
		}
	}

	/// returns the json log lines from the last time the app was launched
	func jsonLogFromLastLaunch() -> String? {
		guard let url = jsonOutputURL, let contents = try? String(contentsOf: url, encoding: .utf8) else {
			Log.warn("Failed to read json log contents")
			return nil
		}
		let lines = contents.components(separatedBy: "\n")
		var startLineNum: Int?
		var endLineNum: Int?
		for lineNum in (0..<lines.count).reversed() {
			guard lines[lineNum].contains("\"type\":\"start\"") else { continue }
			if nil == endLineNum {
				endLineNum = lineNum
			} else {
				startLineNum = lineNum
				break
			}
		}
		guard let start = startLineNum, let end = endLineNum else { return nil }
		return lines[start..<end].joined(separator: "\n")
	}
}

// MARK: - menu handling
extension AppLogger: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		if menu == globalLevelMenu {
			for anItem in menu.items {
				guard let itemLevel = MJLLogLevel(rawValue: anItem.tag) else { continue }
				anItem.state = config.globalLevel == itemLevel ? .on : .off
				anItem.isEnabled = itemLevel != config.globalLevel
			}
			return
		} else if menu == categoryMenuItem?.submenu {
			return
		} else {
			//figure out what category we're dealing  with, and its current value
			guard let cat = menu2Category[menu] else { Log.warn("\(menu) is not associated with a log category"); return }
			var curLevel = OtherLogLevel.default
			if let setLevel = config.logLevel(for: cat) {
				curLevel = OtherLogLevel.from(setLevel)
			}
			// iterate items and set state and isEnabled
			for anItem in menu.items {
				anItem.state = anItem.tag == curLevel.rawValue ? .on : .off
				anItem.isEnabled = anItem.state == .off
			}
		}
	}

	@objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(AppLogger.resetAllCategoriesToDefault(_:)) {
			return config.categoryLevelCount > 0
		}
		return true
	}
}

// MARK: -
class Rc2LogConfig: LogConfiguration {
	let dateFormatter: DateFormatterProtocol
	private var categoryLevels = [LogCategory: MJLLogLevel]()
	var globalLevel: MJLLogLevel = .warn { didSet {
			UserDefaults.standard[.globalLogVersion] = globalLevel.rawValue
		}}
	let levelDescriptions: [MJLLogLevel: NSAttributedString]

	var categoryLevelCount: Int { return categoryLevels.count }
	init() {
		let dformatter = DateFormatter()
		dformatter.locale = Locale(identifier: "en_US_POSIX")
		dformatter.dateFormat = "HH:mm:ss.SSS"
		dateFormatter = dformatter
		levelDescriptions = [
			.critical: NSAttributedString(string: "‼️ CRITICAL"),
			.notice: NSAttributedString(string: "📝 NOTICE"),
			.trace: NSAttributedString(string: "🧵 TRACE"),
			.debug: NSAttributedString(string: "🐞"),
			.error: NSAttributedString(string: "🛑"),
			.warn: NSAttributedString(string: "⚠️"),
			.info: NSAttributedString(string: "ℹ️"),
//			.enter: NSAttributedString(string: "→"),
//			.exit: NSAttributedString(string: "←")
		]
		let defaults = UserDefaults.standard
		if let savedGlobal = MJLLogLevel(rawValue: defaults[.globalLogVersion]) {
			globalLevel = savedGlobal
		}
		if let saved = defaults[.logCategoryLevels] as? [String: Int] {
			categoryLevels = [LogCategory: MJLLogLevel](uniqueKeysWithValues: saved.compactMap
				{ k, v in
					guard let key = LogCategory(rawValue: k), let value = MJLLogLevel(rawValue: v) else { return nil }
					return (key, value)
				})
		}
	}

	func loggingEnabled(level: MJLLogLevel, category: LogCategory) -> Bool {
		if let catLevel = categoryLevels[category] { return level <= catLevel }
		return level <= globalLevel
	}

	func logLevel(for category: LogCategory) -> MJLLogLevel? {
		return categoryLevels[category]
	}

	func set(level: MJLLogLevel?, forCategory category: LogCategory) {
		categoryLevels[category] = level
		let saveDict = Dictionary(uniqueKeysWithValues: categoryLevels.map { k, v in (k.rawValue, v.rawValue) })
		UserDefaults.standard[.logCategoryLevels] = saveDict
	}

	func resetCategoryLevels() {
		categoryLevels.removeAll()
	}

	func description(logLevel: MJLLogLevel) -> NSAttributedString {
		if let desc = levelDescriptions[logLevel] { return desc }
		return NSAttributedString(string: logLevel.description)
	}
}
