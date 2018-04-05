//
//  TemplatesPrefsController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import SwiftyUserDefaults

private extension DefaultsKeys {
	static let lastTemplateType = DefaultsKey<TemplateType>("prefsTemplateType")
}

extension UserDefaults {
	subscript(key: DefaultsKey<TemplateType>) -> TemplateType {
		get { return unarchive(key) ?? .markdown }
		set { archive(key, newValue) }
	}
}

extension NSUserInterfaceItemIdentifier {
	static let templateName = NSUserInterfaceItemIdentifier(rawValue: "name")
}
class TemplatesPrefsController: NSViewController {
	@IBOutlet private var markdownButton: NSButton!
	@IBOutlet private var rCodeButton: NSButton!
	@IBOutlet private var equationButton: NSButton!
	@IBOutlet private var codeOutlineView: NSOutlineView!
	@IBOutlet private var addButton: NSButton!
	@IBOutlet private var removeButton: NSButton!

	var templateManager: CodeTemplateManager!
	private var currentCategories: [CodeTemplateCategory] = []
	
	override func viewDidLoad() {
		super.viewDidLoad()
		codeOutlineView.dataSource = self
		codeOutlineView.delegate = self
		switchTo(type: UserDefaults.standard[.lastTemplateType])
	}
	
	func switchTo(type: TemplateType) {
		switch type {
		case .markdown:
			markdownButton.state = .on
			rCodeButton.state = .off
			equationButton.state = .off
			currentCategories = templateManager.templates(for: .markdown)
		case .rCode:
			rCodeButton.state = .on
			markdownButton.state = .off
			equationButton.state = .off
			currentCategories = templateManager.templates(for: .rCode)
		case .equation:
			equationButton.state = .on
			markdownButton.state = .off
			rCodeButton.state = .off
			currentCategories = templateManager.templates(for: .equation)
		}
		UserDefaults.standard[.lastTemplateType] = type
		codeOutlineView.reloadData()
	}
	
	@IBAction func switchType(_ sender: Any?) {
		guard let button = sender as? NSButton else { return }
		switch button {
		case markdownButton:
			switchTo(type: .markdown)
		case rCodeButton:
			switchTo(type: .rCode)
		case equationButton:
			switchTo(type: .equation)
		default:
			fatalError("invalid action sender")
		}
	}
	
	@IBAction func addItem(_ sender: Any?) {
		addButton.menu?.popUp(positioning: nil, at: addButton.bounds.origin, in: addButton)
	}
	
	@IBAction func addTemplate(_ sender: Any?) {
		
	}
	
	@IBAction func addGroup(_ sender: Any?) {
		var newIndex: Int = currentCategories.count
		var newGroup: CodeTemplateCategory
		defer {
			codeOutlineView.insertItems(at: IndexSet(integer: newIndex), inParent: nil, withAnimation: [])
			guard let cview = codeOutlineView.view(atColumn: 0, row: newIndex, makeIfNecessary: false) as? TemplateCellView else { fatalError() }
			let iset = IndexSet(integer:  codeOutlineView.childIndex(forItem: newGroup))
			codeOutlineView.selectRowIndexes(iset, byExtendingSelection: false)
			cview.beginEditing()
		}
		guard let selection = selectedItem else {
			newIndex = currentCategories.count
			newGroup = insertFolder(at: newIndex)
			return
		}
		if selection is CodeTemplate {
			let parent = codeOutlineView.parent(forItem: selection)!
			let destIndex = codeOutlineView.childIndex(forItem: parent)
			newGroup = insertFolder(at: destIndex)
			newIndex = destIndex
		} else { // selection is category
			newIndex = codeOutlineView.childIndex(forItem: selection)
			newGroup = insertFolder(at: newIndex)
		}
		
	}
	
	@IBAction func removeSelection(_ sender: Any?) {
		
	}
}

extension TemplatesPrefsController: NSOutlineViewDataSource {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if item == nil { return currentCategories.count }
		guard let category = item as? CodeTemplateCategory else { return 0 }
		return category.templates.count
	}
	
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if item == nil { return currentCategories[index] }
		guard let category = item as? CodeTemplateCategory else { fatalError() }
		return category.templates[index]
	}
	
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return item is CodeTemplateCategory
	}
	
	func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
		return item
	}
}

extension TemplatesPrefsController: NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		return item is CodeTemplateCategory
	}
	
	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let templateItem = item as? CodeTemplateObject else { fatalError("invalid item") }
		let view = outlineView.makeView(withIdentifier: .templateName, owner: nil) as! TemplateCellView
		view.templateItem = templateItem
		return view
	}
	
	func outlineViewSelectionDidChange(_ notification: Notification) {
//		let selectedIdx = codeOutlineView.selectedRow
//		guard selectedIdx >= 0 else {
//			removeButton.isEnabled = false
//			return
//		}
//		let selectedItem = codeOutlineView.item(atRow: selectedIdx)
	}
}

extension TemplatesPrefsController {
	private var selectedItem: Any? {
		let index = codeOutlineView.selectedRow
		if index == -1 { return nil }
		return codeOutlineView.item(atRow: index)
	}
	
	/// destIndex of -1 means insert at front
	private func insertFolder(at destIndex: Int) -> CodeTemplateCategory {
		let cat = CodeTemplateCategory(name: "Untitled")
		currentCategories.insert(cat, at: destIndex)
		return cat
	}
	
	private func insertTemplate(in category: CodeTemplateCategory, at index: Int) {
	}
}

// MARK: -

class TemplateCellView: NSTableCellView {
	var templateItem: CodeTemplateObject? { didSet { textField?.stringValue = templateItem?.name ?? "" } }
	
	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		if superview == nil {
			NotificationCenter.default.removeObserver(self, name: NSControl.textDidEndEditingNotification, object: textField!)
		} else {
			NotificationCenter.default.addObserver(self, selector: #selector(editingEnded), name: NSControl.textDidEndEditingNotification, object: textField!)
		}
	}

	func beginEditing() {
		guard let tview = textField as? DoubleClickEditableTextField else { return }
		tview.beginEditing()
	}
	
	@objc func editingEnded() {
		templateItem?.name = textField!.stringValue
	}
}

class TemplatesOutlineView: NSOutlineView {
	override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
		if responder is DoubleClickEditableTextField {
			return true
		}
		return super.validateProposedFirstResponder(responder, for: event)
	}
}
