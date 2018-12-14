//
//  BaseSourceEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 11/8/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import MJLLogger
import ReactiveSwift
import Rc2Common
import Networking
import SyntaxParsing
import ClientCore

class BaseSourceEditorController: AbstractEditorController, TextViewMenuDelegate
{
	// MARK: properties
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	
	var parser: SyntaxParser?
	
	var defaultAttributes: [NSAttributedStringKey: Any] = [:]
	var currentChunkIndex: Int = 0
	
	var searchableTextView: NSTextView? { return editor }
	
	/// true when we should ignore text storage delegate callbacks, such as when deleting the text prior to switching documents
	var ignoreTextStorageNotifications = false
	
	var currentChunk: DocumentChunk? {
		guard let parser = self.parser, parser.chunks.count > 0 else { return nil }
		return parser.chunks[currentChunkIndex]
	}
	
	var currentChunkHasPreviousExecutableChunks: Bool {
		guard let parser = self.parser, parser.executableChunks.count > 0, let curChunk = currentChunk, curChunk.isExecutable
			else { return false }
		// return true if not the first executable chunk
		return parser.executableChunks.index(of: curChunk) ?? 0 > 0
	}
	
	override var documentDirty: Bool {
		guard let edited = editor?.string, let original = context?.currentDocument.value?.savedContents else { return false }
		return edited != original
	}
	
	// MARK: init/deinit
	deinit {
		context?.workspaceNotificationCenter.removeObserver(self)
		context?.notificationCenter.removeObserver(self)
	}
	
	// MARK: methods
	override func setContext(context: EditorContext) {
		super.setContext(context: context)
		context.editorFont.signal.observeValues { [weak self] newFont in
			self?.editor?.font = newFont
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		guard editor != nil else { return }
		editor?.menuDelegate = self
		fileNameField?.stringValue = ""
		editor?.textStorage?.delegate = self
		editor?.enableLineNumberView()
		editor?.textContainer?.replaceLayoutManager(SourceEditorLayoutManager())
		editor?.enclosingScrollView?.rulersVisible = true
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action  {
		case Selector.runQuery, Selector.sourceQuery:
			return context?.currentDocument.value?.currentContents?.count ?? 0 > 0
		case Selector.executeLine:
			if editor?.selectedRange().length ?? 0 > 0 {
				menuItem.title = NSLocalizedString("Execute Selection", comment: "")
			} else {
				menuItem.title = NSLocalizedString("Execute Line", comment: "")
			}
			return editor?.string.count ?? 0 > 0
		default:
			if validateUserInterfaceItem(menuItem) { return true }
			return super.validateMenuItem(menuItem)
		}
	}
	
	func validateUserInterfaceItem(_ anItem: NSValidatedUserInterfaceItem) -> Bool {
		switch anItem.action! as Selector {
		case #selector(ManageFontMenu.adjustFontSize(_:)):
			return true
		case #selector(UsesAdjustableFont.fontChanged(_:)):
			return true
		case #selector(showFindInterface(_:)):
			return !(editor?.enclosingScrollView?.isFindBarVisible ?? false)
		default:
			return false
		}
	}
	
	//returns relevant items from our contextual menu
	func additionalContextMenuItems() -> [NSMenuItem]? {
		var items = [NSMenuItem]()
		for anItem in contextualMenuAdditions?.items ?? [] {
			if let dupItem = anItem.copy() as? NSMenuItem,
				validateMenuItem(dupItem)
			{
				items.append(dupItem)
			}
		}
		return items
	}
	
	// MARK: private methods
	
	override func documentChanged(newDocument: EditorDocument?) {
		guard let editor = self.editor else { Log.error("can't adjust document without editor", .app); return }
		super.documentChanged(newDocument: newDocument)
		if nil == newDocument {
			editor.textStorage?.deleteCharacters(in: editor.rangeOfAllText)
		}
		updateUIForCurrentDocument()
	}
	
	override func loaded(content: String) {
		guard let editor = self.editor, let lm = editor.layoutManager, let storage = editor.textStorage, let txtContainer = editor.textContainer, let document = context!.currentDocument.value
			else { fatalError("editor missing required pieces") }
		ignoreTextStorageNotifications = true
		storage.deleteCharacters(in: editor.rangeOfAllText)
		parser = SyntaxParser(storage: storage, fileType: document.file.fileType, helpCallback: { (topic) -> Bool in
			HelpController.shared.hasTopic(topic) })
		storage.setAttributedString(NSAttributedString(string: content, attributes: self.defaultAttributes))
		let range = storage.string.fullNSRange
		parser?.parseAndAttribute(attributedString: storage, docType: context!.docType, inRange: range, makeChunks: true)
		highlight(attributedString: storage, inRange: range)
		ignoreTextStorageNotifications = false
		if let index = context?.currentDocument.value?.topVisibleIndex, index > 0 {
			//restore the scroll point to the saved character index
			let idx = lm.glyphIndexForCharacter(at: index)
			let point = lm.boundingRect(forGlyphRange: NSRange(location: idx, length: 1), in: txtContainer)
			//postpone to next event loop cycle
			DispatchQueue.main.async {
				editor.enclosingScrollView?.contentView.scroll(to: point.origin)
			}
		}
		self.updateUIForCurrentDocument()
	}
	
	@objc override func editsNeedSaving() {
		guard let document = context?.currentDocument.value, let editor = editor, let lm = editor.layoutManager else { fatalError()}
		guard view.window != nil else { return }
		//save the index of the character at the top left of the text container
		let bnds = editor.enclosingScrollView!.contentView.bounds
		var partial: CGFloat = 1.0
		let idx = lm.characterIndex(for: bnds.origin, in: editor.textContainer!, fractionOfDistanceBetweenInsertionPoints: &partial)
		document.topVisibleIndex = idx
		save(edits: editor.string)
	}
	
	func updateUIForCurrentDocument() {
		let currentDocument = context?.currentDocument.value
		let selected = currentDocument?.file != nil
		runButton?.isEnabled = selected
		sourceButton?.isEnabled = selected
		fileNameField?.stringValue = selected ? currentDocument!.file.name : ""
		editor?.isEditable = selected
		editor?.font = context?.editorFont.value
		// editor.textFinder.cancelFindIndicator() is not erasing the find info, so we have to remove the find interface even if loading another file
		let menuItem = NSMenuItem(title: "foo", action: .findPanelAction, keyEquivalent: "")
		menuItem.tag = Int(NSTextFinder.Action.hideFindInterface.rawValue)
		editor?.performTextFinderAction(menuItem)
		editor?.textFinder.cancelFindIndicator()
		
		willChangeValue(forKey: "canExecute")
		didChangeValue(forKey: "canExecute")
	}
}

// MARK: Actions
extension BaseSourceEditorController {
	@IBAction func showFindInterface(_ sender: Any?) {
		let menuItem = NSMenuItem(title: "foo", action: .findPanelAction, keyEquivalent: "")
		menuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
		editor?.performFindPanelAction(menuItem)
	}
	
	@IBAction override func performTextFinderAction(_ sender: Any?) {
		let menuItem = NSMenuItem(title: "foo", action: .findPanelAction, keyEquivalent: "")
		menuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
		editor?.performFindPanelAction(menuItem)
	}
	
	/// if there is a selection, executes the selection. Otherwise, executes the current line.
	@IBAction func executeCurrentLine(_ sender: AnyObject?) {
		guard let editor = self.editor else { fatalError() }
		let sourceString = editor.string
		let selRange = editor.selectedRange()
		var command: String = ""
		if selRange.length > 0 {
			command = sourceString.substring(from: selRange)!
		} else {
			let lineRange = sourceString.lineRange(for: selRange.toStringRange(sourceString)!)
			command = String(sourceString[lineRange])
		}
		session.executeScript(command)
		if selRange.length < 1 {
			//if execute line, move to next line
			editor.moveCursorToNextNonBlankLine()
		}
	}
}

// MARK: NSTextStorageDelegate
extension BaseSourceEditorController: NSTextStorageDelegate {
	//called when text editing has ended
	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		guard !ignoreTextStorageNotifications else { return }
		ignoreTextStorageNotifications = true
		defer { ignoreTextStorageNotifications = false }
		let range = textStorage.string.fullNSRange
		parser?.parseAndAttribute(attributedString: textStorage, docType: context!.docType, inRange: range, makeChunks: true)
		highlight(attributedString: textStorage, inRange: range)
	}
}

// MARK: NSTextViewDelegate methods
extension BaseSourceEditorController: NSTextViewDelegate {
	func undoManager(for view: NSTextView) -> UndoManager? {
		if let currentDocument = context?.currentDocument.value {
			print("here \(currentDocument)");
			return nil
		} //return currentDocument.undoManager }
		return editor?.undoManager
	}
	
	func textViewDidChangeSelection(_ notification: Notification) {
		guard let parser = parser else { return }
		currentChunkIndex = parser.indexOfChunk(inRange: editor!.selectedRange())
	}
	
	func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
		if let str = link as? String, let pieces = Optional(str.components(separatedBy: ":")), pieces.count == 2 {
			NotificationCenter.default.post(name: .displayHelpTopic, object:pieces[1], userInfo: nil)
			return true
		}
		return false
	}
	
	func textShouldEndEditing(_ textObject: NSText) -> Bool {
		// called when resigning first responder. update the document's contents
		save(edits: editor!.string)
		return true
	}
}
