//
//  ThemePrefsController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy

class ThemePrefsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet var themeListView: NSTableView!
	@IBOutlet var themeTableView: NSTableView!
	@IBOutlet var listFooterView: NSView?
	@IBOutlet var addMenu: NSMenu?
	
	var outputThemes = [OutputTheme]()
	dynamic var selectedTheme: OutputTheme?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		loadThemes()
		selectedTheme = outputThemes.first
		themeListView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		let scrollview = themeListView.enclosingScrollView!
		scrollview.addFloatingSubview(listFooterView!, for: .vertical)
		listFooterView?.setFrameOrigin(NSPoint(x: 0, y: scrollview.bounds.size.height - listFooterView!.bounds.size.height))
	}
	
	@IBAction func addTheme(_ sender: Any?) {
		guard let menu = addMenu?.copy() as? NSMenu, let footer = listFooterView else { fatalError() }
		let bframe = footer.superview!.convert(footer.frame, to: nil)
		let rect = view.window?.convertToScreen(bframe)
		outputThemes.forEach { theme in
			let menuItem = NSMenuItem(title: theme.name, action: #selector(duplicateThemeFromTemplate(_:)), keyEquivalent: "")
			menuItem.tag = outputThemes.index(of: theme)!
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
			let idx = Optional.some(menuItem.tag),
			idx >= 0 && idx < outputThemes.count,
			let theme = Optional.some(outputThemes[idx])
			else { return }
		print("copying \(theme.name)")
	}
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView == themeListView { return outputThemes.count }
		return selectedTheme?.colors.count ?? 0
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		if tableView == themeListView {
			let view = tableView.make(withIdentifier: "themeNameView", owner: nil) as! NSTableCellView
			view.objectValue = outputThemes[row]
			return view
		}
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
			selectedTheme = outputThemes[themeListView.selectedRow]
			themeTableView.reloadData()
		}
	}
	
	private func loadThemes() {
		// AppInfo.subdirectory(type: .applicationSupportDirectory, named: "OutputThemes")
		guard let builtinUrl = Bundle.main.url(forResource: "outputThemes", withExtension: "json"),
			let data = try? Data(contentsOf: builtinUrl),
			let json = try? JSON(data: data)
			else
		{
			fatalError("missing outputThemes.json")
		}
		do {
			outputThemes = try json.decodedArray().sorted(by: { $0.name < $1.name })
			outputThemes.forEach { $0.isBuiltin = true }
		} catch {
			fatalError("failed to load themes: \(error)")
		}
	}
}

class NameAndColorCellView: NSTableCellView {
	@IBOutlet var colorWell: NSColorWell?
}
