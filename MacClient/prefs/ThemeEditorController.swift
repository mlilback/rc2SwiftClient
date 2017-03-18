//
//  ThemeEditorController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Cocoa
import Freddy
import os
import ReactiveSwift
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

	private var wrapper: ThemeWrapper<T>!
	private let themeType: T.Type = T.self
	private var userThemeDirectoryUrl: URL?
	var entries = [ThemeEntry<T>]()
	var selectedTheme: T!
	private var userDirectoryWatcher: DirectoryWatcher?
	private var userThemeUrl: URL!
	private var builtinThemeUrl: URL!

	/// factory function since swift won't let us override init() and call another init method
	static func createInstance<TType: Theme>(userUrl: URL, builtinUrl: URL) -> ThemeEditorController<TType>? {
		let controller = ThemeEditorController<TType>(nibName: "ThemeEditorController", bundle: nil)!
		controller.wrapper = ThemeWrapper<TType>()
		controller.userThemeUrl = userUrl
		controller.builtinThemeUrl = builtinUrl
		return controller
	}
	
	private var indexOfSelectedTheme: Int {
		return entries.index(where: { anEntry in
			guard let aTheme = anEntry.theme else { return false }
			return aTheme.hash == selectedTheme.hash
		}) ?? 0
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		selectedTheme = wrapper.selectedTheme
		setupWatcher()
		updateThemesArray()
		
		themeTable.reloadData()
		themeTable.selectRowIndexes(IndexSet(integer: indexOfSelectedTheme), byExtendingSelection: false)
		let scrollview = themeTable.enclosingScrollView!
		scrollview.addFloatingSubview(themeTable!, for: .vertical)
		themeFooterView?.setFrameOrigin(NSPoint(x: 0, y: scrollview.bounds.size.height - themeFooterView!.bounds.size.height))
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
		view.textField?.stringValue = prop.localizedDescription
		view.colorWell?.color = (selectedTheme?.color[prop])!
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
			propertyTable.reloadData()
			ThemeManager.shared.setActive(theme: selectedTheme)
		}
	}
	
	private func themeDidChange() {
		ThemeManager.shared.setActive(theme: selectedTheme)
		propertyTable.reloadData()
	}
	
	private func updateThemesArray() {
		entries.removeAll()
		let userThemes = wrapper.userThemes
		if !userThemes.isEmpty {
			entries.append(ThemeEntry(title: "User Themes"))
			entries.append(contentsOf: userThemes.map { ThemeEntry(theme: $0) })
			entries.append(ThemeEntry(title: "Default Themes"))
		}
		entries.append(contentsOf: wrapper.builtinThemes.map { ThemeEntry(theme: $0) })
		if entries.count < 1 {
			os_log("no themes!", log: .app, type: .error)
		}
	}
	
	private func setupWatcher() {
		guard nil == userDirectoryWatcher else { return }
		userDirectoryWatcher = DirectoryWatcher(url: userThemeUrl) { [weak self] _ in
			DispatchQueue.main.async {
				self?.updateThemesArray()
				self?.themeTable.reloadData()
			}
		}
	}
}

class NameAndColorCellView: NSTableCellView {
	@IBOutlet var colorWell: NSColorWell?
}
