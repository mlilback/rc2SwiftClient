//
//  TemplatesPrefsController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import ClientCore
import ReactiveSwift
import SwiftyUserDefaults
import MJLLogger

// MARK: - UserDefaults support for saving TemplateType values
private extension DefaultsKeys {
	static let lastTemplateType = DefaultsKey<TemplateType>("prefsTemplateType")
}

extension UserDefaults {
	subscript(key: DefaultsKey<TemplateType>) -> TemplateType {
		get { return unarchive(key) ?? .markdown }
		set { archive(key, newValue) }
	}
}

// MARK: - outline cell identifiers
extension NSUserInterfaceItemIdentifier {
	static let templateName = NSUserInterfaceItemIdentifier(rawValue: "name")
}

// MARK: - main controller
class TemplatesPrefsController: NSViewController {
	let templatePasteboardType = NSPasteboard.PasteboardType(rawValue: "io.rc2.client.codeTemplate")

	// MARK: properties
	@IBOutlet private var splitterView: NSSplitView!
	@IBOutlet private var markdownButton: NSButton!
	@IBOutlet private var rCodeButton: NSButton!
	@IBOutlet private var equationButton: NSButton!
	@IBOutlet private var codeOutlineView: NSOutlineView!
	@IBOutlet private var addButton: NSButton!
	@IBOutlet private var addCategoryButton: NSButton!
	@IBOutlet private var removeButton: NSButton!
	@IBOutlet private var nameEditField: NSTextField!
	@IBOutlet private var codeEditView: NSTextView!

	var templateManager: CodeTemplateManager!
	private var currentCategories: [CodeTemplateCategory] = []
	private var editingDisposables = CompositeDisposable()
	private var currentType: TemplateType = .markdown
	private var currentTemplate: CodeTemplate?
	private let _undoManager = UndoManager()
	private let selectionMarkerRegex = try! NSRegularExpression(pattern: CodeTemplate.selectionTemplateKey, options: [.caseInsensitive, .ignoreMetacharacters])
	private let selectionMarkerColor =  NSColor(calibratedRed: 0.884, green: 0.974, blue: 0.323, alpha: 1.0)
	private var lastSelectionMarkerRange: NSRange?
	private var manuallyExpanding: Bool = false
	
	override var undoManager: UndoManager? { return _undoManager }
	override var acceptsFirstResponder: Bool { return true }
	
	// MARK: - methods
	override func viewDidLoad() {
		super.viewDidLoad()
		codeOutlineView.dataSource = self
		codeOutlineView.delegate = self
		splitterView.delegate = self
		nameEditField.delegate = self
		codeEditView.delegate = self
		switchTo(type: UserDefaults.standard[.lastTemplateType])
		// setup add template icon
		let folderImage = NSImage(named: .folder)!
		let addImage = NSImage(named: .addTemplate)!
		folderImage.overlay(image: addImage)
		addCategoryButton.image = folderImage
		codeOutlineView.registerForDraggedTypes([templatePasteboardType])
		codeOutlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
	}
	
	override func viewDidDisappear() {
		super.viewDidDisappear()
		_ = try? templateManager.saveAll()
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
		switch action {
		case #selector(addTemplate(_:)),
			 #selector(duplicateSelection(_:)),
			 #selector(deleteBackward(_:)): // something must be selected
			return codeOutlineView.selectedRow != -1
		case #selector(addCategory(_:)):
			return true
		default:
			return super.validateMenuItem(menuItem)
		}
	}
	
	func switchTo(type: TemplateType) {
		switch type {
		case .markdown:
			markdownButton.state = .on
			rCodeButton.state = .off
			equationButton.state = .off
			currentCategories = templateManager.categories(for: .markdown)
		case .rCode:
			rCodeButton.state = .on
			markdownButton.state = .off
			equationButton.state = .off
			currentCategories = templateManager.categories(for: .rCode)
		case .equation:
			equationButton.state = .on
			markdownButton.state = .off
			rCodeButton.state = .off
			currentCategories = templateManager.categories(for: .equation)
		}
		UserDefaults.standard[.lastTemplateType] = type
		currentType = type
		codeOutlineView.reloadData()
	}
	
	// MARK: - actions
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
	
	@IBAction func duplicateSelection(_ sender: Any?) {
		
	}
	
	@IBAction override func deleteBackward(_ sender: Any?) {
		guard let selItem = selectedItem else { fatalError("how was delete called with no selection?") }
		guard let cat = selItem as? CodeTemplateCategory else {
			delete(template: selItem as! CodeTemplate)
			return
		}
		delete(category: cat)
	}

	/// adds a CodeTemplate
	@IBAction func addTemplate(_ sender: Any?) {
		guard let selection = selectedItem else { fatalError("adding template w/o selection") }
		var parent: CodeTemplateCategory
		var newIndex: Int
		if selection is CodeTemplate {
			// add after this one
			parent = codeOutlineView.parent(forItem: selection) as! CodeTemplateCategory
			newIndex = codeOutlineView.childIndex(forItem: selection) + 1
		} else { // is a category
			parent = selection as! CodeTemplateCategory
			newIndex = 0
		}
		// have to be expanded to insert an item
		if !codeOutlineView.isItemExpanded(parent) {
			codeOutlineView.expandItem(parent)
		}
		let template = CodeTemplate(name: "Untitled", contents: "", type: currentType)
		undoManager?.registerUndo(withTarget: self) { [theTemplate = template] (me) -> Void in
			me.remove(template: theTemplate)
		}
		insert(template: template, in: parent, at: newIndex)
		view.window?.makeFirstResponder(nameEditField)
	}

	/// adds a CodeTemplateCategory
	@IBAction func addCategory(_ sender: Any?) {
		var newIndex: Int = currentCategories.count
		var newGroup: CodeTemplateCategory
		defer {
			insert(category: newGroup, at: newIndex)
			codeOutlineView.expandItem(newGroup)
			view.window?.makeFirstResponder(nameEditField)
		}
		guard let selection = selectedItem else {
			newIndex = currentCategories.count
			newGroup = templateManager.createCategory(of: currentType, at: newIndex)
			return
		}
		if selection is CodeTemplate {
			let parent = codeOutlineView.parent(forItem: selection)!
			let destIndex = codeOutlineView.childIndex(forItem: parent)
			newGroup = templateManager.createCategory(of: currentType, at: destIndex)
			newIndex = destIndex
		} else { // selection is category
			newIndex = codeOutlineView.childIndex(forItem: selection)
			newGroup = templateManager.createCategory(of: currentType, at: newIndex)
		}
	}
}

// MARK: - NSOutlineViewDataSource
extension TemplatesPrefsController: NSOutlineViewDataSource {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if item == nil { return currentCategories.count }
		guard let category = item as? CodeTemplateCategory else { return 0 }
		return category.templates.value.count
	}
	
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if item == nil { return currentCategories[index] }
		guard let category = item as? CodeTemplateCategory else { fatalError() }
		return category.templates.value[index]
	}
	
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return item is CodeTemplateCategory
	}
	
	func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
		return item
	}

	// implement so autosave expanded items works, or manually implement
//	func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
//
//	}
	
	func outlineView(_ outlineView: NSOutlineView, writeItems items: [Any], to pasteboard: NSPasteboard) -> Bool
	{
		guard items.count == 1 else { return false }
		let wrapper = DragData(items[0])
		pasteboard.setData(wrapper.encode(), forType: templatePasteboardType)
		return true
	}
	
	func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem parentItem: Any?, proposedChildIndex index: Int) -> NSDragOperation
	{
		guard let wrapperData = info.draggingPasteboard().data(forType: templatePasteboardType), let wrapper = try? JSONDecoder().decode(DragData.self, from: wrapperData)
			else { Log.warn("asked to validate invalid drag data", .app); return [] }
		let destObj = parentItem as? CodeTemplateObject
		let dropOperation = (info.draggingSourceOperationMask() == [.copy]) ? NSDragOperation.copy : NSDragOperation.move
		//print("validate drop of \(wrapper) to \(destObj?.description ?? "root") @ \(index) as \(info.draggingSourceOperationMask())")
		// breaking from the switch will return [.move, .copy]
		if wrapper.isCategory {
			switch destObj {
			case nil: // proposed is root, which is fine
				return dropOperation
			case is CodeTemplateCategory:
				outlineView.setDropItem(nil, dropChildIndex: outlineView.childIndex(forItem: destObj!) + 1)
			case is CodeTemplate:
				outlineView.setDropItem(nil, dropChildIndex: outlineView.childIndex(forItem: outlineView.parent(forItem: destObj!)!))
			default:
				return []
			}
			return dropOperation
		}
		// dragging a template
		if destObj == nil { return [] } // don't allow a template at the root level
		return dropOperation
	}
	
	func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool
	{
		return false
	}
}

// MARK: - NSOutlineViewDelegate
extension TemplatesPrefsController: NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let templateItem = item as? CodeTemplateObject else { fatalError("invalid item") }
		let view = outlineView.makeView(withIdentifier: .templateName, owner: nil) as! TemplateCellView
		view.templateItem = templateItem
		return view
	}
	
	func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
		let result = item is CodeTemplateCategory
		if !manuallyExpanding, NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
			// expand them all
			manuallyExpanding = true
			DispatchQueue.main.async {
				self.codeOutlineView.expandItem(nil, expandChildren: true)
				self.manuallyExpanding = false
			}
		}
		return result
	}
	
	func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
		let result = item is CodeTemplateCategory
		if !manuallyExpanding, NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
			// collapse them all
			manuallyExpanding = true
			DispatchQueue.main.async {
				self.codeOutlineView.collapseItem(nil, collapseChildren: true)
				self.manuallyExpanding = false
			}
		}
		return result
	}
	
	func outlineViewSelectionDidChange(_ notification: Notification) {
		editingDisposables.dispose()
		editingDisposables = CompositeDisposable()
		currentTemplate = nil
		let indexes = codeOutlineView.selectedRowIndexes
		defer {
			nameEditField.isEnabled = indexes.count > 0
			removeButton.isEnabled = indexes.count > 0
			addButton.isEnabled = indexes.count > 0
		}
		guard indexes.count > 0 else {
			nameEditField.stringValue = ""
			codeEditView.textStorage!.setAttributedString(NSAttributedString(string: ""))
			return
		}
		guard let item = codeOutlineView.item(atRow: indexes.first!) else { fatalError("slection not valid object") }
		if let cat = item as? CodeTemplateCategory {
			editingDisposables += nameEditField.reactive.stringValue <~ cat.name
			editingDisposables += cat.name <~ nameEditField.reactive.continuousStringValues
			codeEditView.textStorage?.setAttributedString(NSAttributedString(string: ""))
			codeEditView.isEditable = false
		} else if let template = item as? CodeTemplate {
			editingDisposables += nameEditField.reactive.stringValue <~ template.name
			editingDisposables += template.name <~ nameEditField.reactive.continuousStringValues
			codeEditView.textStorage?.replaceCharacters(in: codeEditView.string.fullNSRange, with: template.contents.value)
//			editingDisposables += codeEditView.reactive.textValue <~ template.contents
//			editingDisposables += template.contents <~ codeEditView.reactive.continuousStringValues
			codeEditView.isEditable = true
			currentTemplate = template
			colorizeSelectionMarker()
		}
	}
}

// MARK: - NSSplitViewDelegate
extension TemplatesPrefsController: NSSplitViewDelegate {
	func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat
	{
		return 120
	}
	
	func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat
	{
		return splitView.frame.size.height - 120
	}
}

// MARK: - NSTextFieldDelegate
extension TemplatesPrefsController: NSTextFieldDelegate {
	override func controlTextDidEndEditing(_ obj: Notification) {
		_ = try? templateManager.save(type: currentType)
	}
}

// MARK: - NSTextViewDelegate
extension TemplatesPrefsController: NSTextViewDelegate {
	func textDidChange(_ notification: Notification) {
		colorizeSelectionMarker()
		if codeEditView.isEditable {
			currentTemplate?.contents.value = codeEditView.string
		}
	}
}

// MARK: - private
extension TemplatesPrefsController {
	/// the currently selected template/category, or nil if there is no selection
	private var selectedItem: Any? {
		let index = codeOutlineView.selectedRow
		if index == -1 { return nil }
		return codeOutlineView.item(atRow: index)
	}
	
	private func colorizeSelectionMarker() {
		guard let selMatch = selectionMarkerRegex.firstMatch(in: codeEditView.string, options: [], range: codeEditView.string.fullNSRange)
			else { removeSelectionMarker(); return }
		let last = lastSelectionMarkerRange ?? NSRange(location: 0, length: 0)
		guard last != selMatch.range else { return } // no change
		removeSelectionMarker()
		codeEditView.layoutManager?.addTemporaryAttribute(.backgroundColor, value: selectionMarkerColor, forCharacterRange: selMatch.range)
		lastSelectionMarkerRange = selMatch.range
	}
	
	private func removeSelectionMarker() {
		if lastSelectionMarkerRange != nil {
			// the range might have changed, and we won't know unless we switch to using NSTextStorageDelegate instead of NSTextViewDelegate. so we'll just remove the background color from everywhere
			codeEditView.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: codeEditView.string.fullNSRange)
			lastSelectionMarkerRange = nil
		}
	}
	
	/// inserts a new category. separate function for undo
	private func insert(category: CodeTemplateCategory, at index: Int) {
		currentCategories.insert(category, at: index)
		codeOutlineView.insertItems(at: IndexSet(integer: index), inParent: nil, withAnimation: [])
		let iset = IndexSet(integer: codeOutlineView.row(forItem: category))
		codeOutlineView.selectRowIndexes(iset, byExtendingSelection: false)
	}

	/// actually removes the category from storage
	private func remove(category: CodeTemplateCategory) {
		let index = codeOutlineView.childIndex(forItem: category)
		currentCategories.remove(at: index)
		templateManager.set(categories: currentCategories, for: currentType)
		codeOutlineView.removeItems(at: IndexSet(integer: index), inParent: nil, withAnimation: .slideUp)
	}
	
	/// deletes category with undo
	private func delete(category: CodeTemplateCategory) {
		let index = codeOutlineView.childIndex(forItem: category)
		let undoAction = { (me: TemplatesPrefsController) -> Void in
			me.insert(category: category, at: index)
		}
		if category.templates.value.count == 0 {
			// if no templates, don't require conformation
			self.undoManager?.registerUndo(withTarget: self, handler: undoAction)
			self.remove(category: category)
			return
		}
		confirmAction(message: NSLocalizedString("DeleteCodeTemplateWarning", comment: ""),
					  infoText: NSLocalizedString("DeleteCodeTemplateWarningInfo", comment: ""), buttonTitle: NSLocalizedString("Delete", comment: ""))
		{ confirmed in
			guard confirmed else { return }
			self.undoManager?.registerUndo(withTarget: self, handler: undoAction)
			self.remove(category: category)
		}
	}
	
	/// insert a new template. separate function for undo purposes
	private func insert(template: CodeTemplate, in parent: CodeTemplateCategory, at index: Int) {
		parent.templates.value.insert(template, at: index)
		codeOutlineView.insertItems(at: IndexSet(integer: index), inParent: parent, withAnimation: [])
		codeOutlineView.selectRowIndexes(IndexSet(integer: codeOutlineView.row(forItem: template)), byExtendingSelection: false)
	}
	
	/// actually removes the template visually and from storage
	private func remove(template: CodeTemplate) {
		guard let parent = codeOutlineView.parent(forItem: template) as? CodeTemplateCategory,
				let index = Optional.some(codeOutlineView.childIndex(forItem: template)), index != -1
			else { Log.error("", .app); return }
		parent.templates.value.remove(at: index)
		codeOutlineView.removeItems(at: IndexSet(integer: index), inParent: parent, withAnimation: .slideUp)
	}

	/// deletes template with undo, cofirming with user if necessary
	private func delete(template: CodeTemplate) {
		let defaults = UserDefaults.standard
		// create local variables to enforce capture of current values
		let parent = codeOutlineView.parent(forItem: template) as! CodeTemplateCategory
		let index = codeOutlineView.childIndex(forItem: template)
		// create closure that will do the reverse
		let undoAction = { (me: TemplatesPrefsController) -> Void in
			me.insert(template: template, in: parent, at: index)
		}
		let actuallyRemove = {
			self.undoManager?.registerUndo(withTarget: self, handler: undoAction)
			self.remove(template: template)
		}
		guard !defaults[.suppressDeleteTemplate] else {
			actuallyRemove()
			return
		}
		// need to confirm deletion with user
		confirmAction(message: NSLocalizedString("DeleteCodeTemplateWarning", comment: ""),
					  infoText: NSLocalizedString("DeleteCodeTemplateWarningInfo", comment: ""), buttonTitle: NSLocalizedString("Delete", comment: ""), suppressionKey: .suppressDeleteTemplate)
		{ confirmed in
			guard confirmed else { return }
			actuallyRemove()
		}
	}
}

// MARK: - NSTextView
// adds a binding target of textValue to NSTextView
extension Reactive where Base: NSTextView {
	public var textValue: BindingTarget<String> {
		return makeBindingTarget { (view, string) in
			let selection = view.selectedRanges
			view.replaceCharacters(in: view.string.fullNSRange, with: string)
			view.selectedRanges = selection
		}
	}
}

// MARK: - helper types

fileprivate struct DragData: Codable, CustomStringConvertible {
	let category: CodeTemplateCategory?
	let template: CodeTemplate?
	var isCategory: Bool { return category != nil }
	var description: String { return isCategory ? category!.description : template!.description }
	var item: CodeTemplateObject { return isCategory ? category! : template! }
	
	init(category: CodeTemplateCategory) {
		self.category = category
		self.template = nil
	}
	
	init(template: CodeTemplate) {
		self.template = template
		self.category = nil
	}
	
	init(_ item: Any) {
		if let titem = item as? CodeTemplate {
			self.template = titem
			self.category = nil
		} else if let tcat = item as? CodeTemplateCategory {
			self.category = tcat
			self.template = nil
		} else {
			fatalError("invalid drag object")
		}
	}
	
	func encode() -> Data {
		return try! JSONEncoder().encode(self)
	}
}

class TemplateCellView: NSTableCellView {
	var templateItem: CodeTemplateObject? { didSet { templateItemWasSet() } }
	private var disposable: Disposable?
	
	private func templateItemWasSet() {
		disposable?.dispose()
		assert(textField != nil)
		textField!.reactive.stringValue <~ templateItem!.name
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
