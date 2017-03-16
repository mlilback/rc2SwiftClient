//
//  ThemeEditorController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Cocoa
import Freddy
import os
import SwiftyUserDefaults

// wrapper used for table rows in the themeList
struct ThemeEntry<T: Theme> {
	let title: String
	let theme: T?
	var isSectionLabel: Bool { return theme == nil }
	
	init(title: String? = nil, theme: T? = nil) {
		precondition(title != nil || theme != nil)
		self.theme = theme
		self.title = title == nil ? theme!.name: title!
	}
}

class ThemeEditorController<T: Theme>: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet var themeTable: NSTableView!
	@IBOutlet var propertyTable: NSTableView!
	@IBOutlet var themeFooterView: NSView!
	@IBOutlet var addMenuTemplate: NSMenu!
	@IBOutlet var removeButton: NSButton!

	private let themeType: T.Type = T.self
	private var userThemeDirectoryUrl: URL?
	private var defaultThemes = [T]()
	private var userThemes = [T]()
	var entries = [ThemeEntry<T>]()
	var selectedTheme: T? { didSet { themeDidChange() } }
	private var userDirectoryWatcher: DirectoryWatcher?
	private var userThemeUrl: URL!
	private var builtinThemeUrl: URL!

	/// factory function since swift won't let us override init() and call another init method
	static func createInstance<TType: Theme>(userUrl: URL, builtinUrl: URL) -> ThemeEditorController<TType>? {
		let controller = ThemeEditorController<TType>(nibName: "ThemeEditorController", bundle: nil)!
		controller.userThemeUrl = userUrl
		controller.builtinThemeUrl = builtinUrl
		return controller
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		loadSystemThemes()
		loadUserThemes()
		updateThemesArray()
		selectedTheme = entries.first(where: { !$0.isSectionLabel })?.theme
		themeTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		let scrollview = themeTable.enclosingScrollView!
		scrollview.addFloatingSubview(themeTable!, for: .vertical)
		themeFooterView?.setFrameOrigin(NSPoint(x: 0, y: scrollview.bounds.size.height - themeFooterView!.bounds.size.height))
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		themeTable.reloadData()
	}
	
	@IBAction func addTheme(_ sender: Any?) {
		guard let menu = addMenuTemplate?.copy() as? NSMenu, let footer = themeFooterView else { fatalError() }
		let bframe = footer.superview!.convert(footer.frame, to: nil)
		let rect = view.window?.convertToScreen(bframe)
		entries.forEach { entry in
			guard let theme = entry.theme else { return }
			let menuItem = NSMenuItem(title: theme.name, action: #selector(duplicateThemeFromTemplate(_:)), keyEquivalent: "")
			menuItem.representedObject = theme
			menuItem.target = self
			menu.addItem(menuItem)
		}
		menu.popUp(positioning: nil, at: rect!.origin, in: nil)
	}
	
	@IBAction func removeTheme(_ sender: Any?) {
		print("remove theme")
	}
	
	@IBAction func cloneTheme(_ sender: Any?) {
		
	}
	
	@IBAction func duplicateThemeFromTemplate(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem,
			let template = menuItem.representedObject as? T
			else { return }
		print("copying \(template.name)")
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView == themeTable { return entries.count }
		return selectedTheme?.propertyCount ?? 0
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		if tableView == themeTable {
			// swiftlint:disable:next force_cast
			let view = tableView.make(withIdentifier: "themeNameView", owner: nil) as! NSTableCellView
			view.textField?.stringValue = entries[row].title
			return view
		}
		// swiftlint:disable:next force_cast
		let view = tableView.make(withIdentifier: "themeItem", owner: nil) as! NameAndColorCellView
		let prop = T.Property.allProperties[row]
		view.textField?.stringValue = prop.stringValue
		view.colorWell?.color = (selectedTheme?.color(for: prop))!
		view.colorWell?.isEnabled = !(selectedTheme?.isBuiltin ?? false)
		return view
	}
	
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if tableView == propertyTable { return false }
		return true
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		if notification.object as? NSTableView == themeTable {
			selectedTheme = entries[themeTable.selectedRow].theme
		}
	}
	
	private func themeDidChange() {
		UserDefaults.standard[.activeOutputTheme] = selectedTheme?.toJSON()
		NotificationCenter.default.post(name: .outputThemeChanged, object: selectedTheme)
		propertyTable.reloadData()
	}
	
	private func updateThemesArray() {
		entries.removeAll()
		if userThemes.count > 0 {
			entries.append(ThemeEntry(title: "User Themes"))
			entries.append(contentsOf: userThemes.map { ThemeEntry(theme: $0) })
			entries.append(ThemeEntry(title: "Default Themes"))
		}
		entries.append(contentsOf: defaultThemes.map { ThemeEntry(theme: $0) })
		if entries.count < 1 {
			os_log("no themes!", log: .app, type: .error)
		}
	}
	
	private func loadSystemThemes() {
		defaultThemes = T.loadThemes(from: builtinThemeUrl, builtin: true)
	}
	
	private func loadUserThemes() {
		//create watcher if necessary
		if nil == userDirectoryWatcher {
			userDirectoryWatcher = DirectoryWatcher(url: userThemeUrl) {_ in
				DispatchQueue.main.async {
					self.loadUserThemes()
				}
			}
		}
		userThemes = T.loadThemes(from: userThemeUrl, builtin: false)
	}
}

class NameAndColorCellView: NSTableCellView {
	@IBOutlet var colorWell: NSColorWell?
}
