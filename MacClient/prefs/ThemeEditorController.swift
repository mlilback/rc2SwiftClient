//
//  ThemeEditorController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Cocoa
import Freddy
import MJLLogger
import ReactiveSwift
import SwiftyUserDefaults

enum ThemeType {
	case syntax(SyntaxTheme)
	case output(OutputTheme)
}

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

class ThemeEditorController<T: BaseTheme>: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate
{
	// MARK: properties
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
	private var ignoreSelectionChange: Bool = false

	private var indexOfSelectedTheme: Int {
		return entries.index(where: { anEntry in
			guard let aTheme = anEntry.theme else { return false }
			return aTheme == selectedTheme
		}) ?? 0
	}
	
	/// factory function since swift won't let us override init() and call another init method
	static func createInstance<TType>(userUrl: URL, builtinUrl: URL) -> ThemeEditorController<TType>? {
		let controller = ThemeEditorController<TType>(nibName: NSNib.Name(rawValue: "ThemeEditorController"), bundle: nil)
		controller.wrapper = ThemeWrapper<TType>()
		controller.userThemeUrl = userUrl
		controller.builtinThemeUrl = builtinUrl
		return controller
	}
	
	// MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		selectedTheme = wrapper.selectedTheme
		setupWatcher()
		updateThemesArray()
		
		themeTable.reloadData()
		themeTable.selectRowIndexes(IndexSet(integer: indexOfSelectedTheme), byExtendingSelection: false)
//		let scrollview = themeTable.enclosingScrollView!
//		scrollview.addFloatingSubview(themeFooterView!, for: .vertical)
//		let floatOrigin = NSPoint(x: 0, y: scrollview.bounds.size.height - themeFooterView!.bounds.size.height - 50)
//		print("origin = \(themeFooterView!.frame)")
//		themeFooterView?.setFrameOrigin(floatOrigin)
//		themeFooterView!.translatesAutoresizingMaskIntoConstraints = false
//		themeFooterView.heightAnchor.constraint(equalToConstant: 30.0)
//		scrollview.addSubview(themeFooterView!)
//		scrollview.addConstraint(NSLayoutConstraint(item: themeFooterView!, attribute: .leading, relatedBy: .equal, toItem: scrollview, attribute: .leading, multiplier: 1.0, constant: 0))
//		scrollview.addConstraint(NSLayoutConstraint(item: themeFooterView!, attribute: .trailing, relatedBy: .equal, toItem: scrollview, attribute: .trailing, multiplier: 1.0, constant: 0))
//		scrollview.addConstraint(NSLayoutConstraint(item: themeFooterView!, attribute: .bottom, relatedBy: .equal, toItem: scrollview, attribute: .bottom, multiplier: 1.0, constant: 10.0))
	}
	
	// MARK: - tableView methods
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView == themeTable { return entries.count }
		return selectedTheme?.propertyCount ?? 0
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		if tableView == themeTable {
			guard entries[row].isSectionLabel else {
				// swiftlint:disable:next force_cast
				let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("themeNameView"), owner: nil) as! NSTableCellView
				guard let themeEditField = view.textField as? ThemeNameEditField else { fatalError() }
				themeEditField.entryIndex = row
				themeEditField.stringValue = entries[row].title
				themeEditField.delegate = self
				themeEditField.action = #selector(editTextField(_:))
				// name only editable for non-builtin themes
				themeEditField.isEditable = !entries[row].theme!.isBuiltin
				return view
			}
			// swiftlint:disable:next force_cast
			let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("themeGroupView"), owner: nil) as! NSTableCellView
			view.textField?.stringValue = entries[row].title
			return view
		}
		// swiftlint:disable:next force_cast
		let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("themeItem"), owner: nil) as! NameAndColorCellView
		let prop = selectedTheme!.allProperties[row]
		view.textField?.stringValue = prop.localizedDescription
		view.colorWell?.color = selectedTheme!.color(for: prop)
		view.colorWell?.isEnabled = !(selectedTheme?.isBuiltin ?? false)
		view.colorWell?.tag = row //store row index
		view.colorWell?.action = #selector(colorChanged(_:))
		view.colorWell?.target = self
		return view
	}
	
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		if tableView == propertyTable { return false }
		return !entries[row].isSectionLabel
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		if notification.object as? NSTableView == themeTable && !ignoreSelectionChange {
			selectedTheme = entries[themeTable.selectedRow].theme
			propertyTable.reloadData()
			ThemeManager.shared.setActive(theme: selectedTheme)
		}
	}
	
	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		guard tableView == themeTable else { return nil }
		guard entries[row].isSectionLabel else { return nil }
		let view = GroupRowView()
//		view.isGroupRowStyle = true
		view.backgroundColor = NSColor.lightGray//.withAlphaComponent(0.8)
		return view
	}
	
	func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		guard tableView == themeTable else { return false }
		guard row >= 0 && row < entries.count else { return false }
		return entries[row].isSectionLabel
	}

	// MARK: - actions
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
	
	@IBAction func duplicateThemeFromTemplate(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem,
			let template = menuItem.representedObject as? T
			else { return }
		selectedTheme = ThemeManager.shared.duplicate(theme: template)
		ThemeManager.shared.setActive(theme: selectedTheme)
		updateThemesArray()
		ignoreSelectionChange = true
		themeTable.reloadData()
		ignoreSelectionChange = false
		themeTable.selectRowIndexes(IndexSet(integer: indexOfSelectedTheme), byExtendingSelection: false)
		propertyTable.reloadData()
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
			let pview = self.themeTable.view(atColumn: 0, row: self.indexOfSelectedTheme, makeIfNecessary: false) as! NSTableCellView
			self.view.window?.makeFirstResponder(pview.textField)
		}
	}
	
	@IBAction func editTextField(_ sender: Any?) {
		guard let editor = sender as? ThemeNameEditField,
			let rowNum = Optional(editor.entryIndex),
			rowNum >= 0,
			let theme = entries[rowNum].theme
		else { print("not valid editor"); return }
		print("set \(theme.name) to \(editor.stringValue)")
	}
	
	@IBAction func colorChanged(_ sender: Any?) {
		guard let cwell = sender as? NSColorWell else { fatalError("wtf") }
		print("set \(cwell.tag) to \(cwell.color)")
	}

	// MARK: - private methods
	
	private func themeFor(control: NSControl) -> T? {
		let rowNum = propertyTable.row(for: control)
		guard rowNum != -1 else { return nil }
		return entries[rowNum].theme
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
			entries.append(contentsOf: userThemes.sorted(by: { $0.name < $1.name }).map({ ThemeEntry(theme: $0) }))
			entries.append(ThemeEntry(title: "Default Themes"))
		}
		entries.append(contentsOf: wrapper.builtinThemes.sorted(by: { $0.name < $1.name }).map { ThemeEntry(theme: $0) })
		if entries.count < 1 {
			Log.error("no themes!", .app)
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

// MARK: -
class GroupRowView: NSTableRowView {
//	override var interiorBackgroundStyle: NSBackgroundStyle { return .lowered }
}

class GroupCellView: NSTableCellView {
	override var isOpaque: Bool { return true }
}

class NameCellView: NSTableCellView {
}

class NameAndColorCellView: NSTableCellView {
	@IBOutlet var colorWell: NSColorWell?
}

/// a NSTextField with a property that stores the index of the property being edited
class ThemeNameEditField: NSTextField {
	var entryIndex: Int = -1
}
