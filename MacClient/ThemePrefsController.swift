//
//  ThemePrefsController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import ClientCore
import os
import SwiftyUserDefaults
import Networking

// wrapper used for table rows in the themeList
struct ThemeEntry {
	let title: String
	let theme: OutputTheme?
	var isSectionLabel: Bool { return theme == nil }

	init(title: String? = nil, theme: OutputTheme? = nil) {
		precondition(title != nil || theme != nil)
		self.theme = theme
		self.title = title == nil ? theme!.name: title!
	}
}

class ThemePrefsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet var themeListView: NSTableView!
	@IBOutlet var themeTableView: NSTableView!
	@IBOutlet var listFooterView: NSView?
	@IBOutlet var addMenu: NSMenu?
	
	private var userThemeDirectoryUrl: URL?
	private var defaultThemes = [OutputTheme]()
	private var userThemes = [OutputTheme]()
	var entries = [ThemeEntry]()
	dynamic var selectedTheme: OutputTheme? { didSet { saveActiveTheme() } }
	private var userDirectoryWatcher: DirectoryWatcher?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		loadSystemThemes()
		loadUserThemes()
		updateThemesArray()
		selectedTheme = entries.first(where: { !$0.isSectionLabel })?.theme
		themeListView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		let scrollview = themeListView.enclosingScrollView!
		scrollview.addFloatingSubview(listFooterView!, for: .vertical)
		listFooterView?.setFrameOrigin(NSPoint(x: 0, y: scrollview.bounds.size.height - listFooterView!.bounds.size.height))
	}
	
	@IBAction func addTheme(_ sender: Any?) {
		guard let menu = addMenu?.copy() as? NSMenu, let footer = listFooterView else { fatalError() }
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
			let template = menuItem.representedObject as? OutputTheme
			else { return }
		print("copying \(template.name)")
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView == themeListView { return entries.count }
		return selectedTheme?.propertyCount ?? 0
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		if tableView == themeListView {
			// swiftlint:disable:next force_cast
			let view = tableView.make(withIdentifier: "themeNameView", owner: nil) as! NSTableCellView
			view.textField?.stringValue = entries[row].title
			return view
		}
		// swiftlint:disable:next force_cast
		let view = tableView.make(withIdentifier: "themeItem", owner: nil) as! NameAndColorCellView
		let prop = OutputThemeProperty.allValues[row]
		view.textField?.stringValue = prop.rawValue
		view.colorWell?.color = (selectedTheme?.color(for: prop))!
		view.colorWell?.isEnabled = !(selectedTheme?.isBuiltin ?? false)
		return view
	}
	
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if tableView == themeTableView { return false }
		return true
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		if notification.object as? NSTableView == themeListView {
			selectedTheme = entries[themeListView.selectedRow].theme
			saveActiveTheme()
			themeTableView.reloadData()
		}
	}
	
	private func saveActiveTheme() {
		UserDefaults.standard[.activeOutputTheme] = selectedTheme?.toJSON()
		NotificationCenter.default.post(name: .outputThemeChanged, object: selectedTheme)
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
		//load system themes
		guard let builtinUrl = Bundle.main.url(forResource: "outputThemes", withExtension: "json"),
			let data = try? Data(contentsOf: builtinUrl),
			let json = try? JSON(data: data)
			else
		{
			fatalError("missing outputThemes.json")
		}
		do {
			defaultThemes = try json.decodedArray().sorted(by: { $0.name < $1.name })
			defaultThemes.forEach { $0.isBuiltin = true }
		} catch {
			fatalError("failed to load themes: \(error)")
		}
	}
	
	private func loadUserThemes() {
		do {
			//create watcher if necessary
			if nil == userDirectoryWatcher {
				userThemeDirectoryUrl = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "OutputThemes")
				userDirectoryWatcher = DirectoryWatcher(url: userThemeDirectoryUrl!) {_ in
					DispatchQueue.main.async {
						self.loadUserThemes()
					}
				}
			}
			//scan for themes
			userThemes.removeAll()
			let urls = try FileManager.default.contentsOfDirectory(at: userThemeDirectoryUrl!, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
			urls.forEach { aFile in
				guard aFile.pathExtension == "json",
					let data = try? Data(contentsOf: aFile),
					let json = try? JSON(data: data),
					let theme: OutputTheme = try? json.decode()
					else { return }
				userThemes.append(theme)
			}
		} catch {
			os_log("error loading user themes: %{public}s", log: .app, error.localizedDescription)
		}
	}
}

class NameAndColorCellView: NSTableCellView {
	@IBOutlet var colorWell: NSColorWell?
}
