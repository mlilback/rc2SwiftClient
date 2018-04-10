//
//  SourceEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import Freddy
import ReactiveSwift
import Rc2Common
import Networking
import SyntaxParsing
import ClientCore

class SourceEditorController: AbstractEditorController, TextViewMenuDelegate
{
	// MARK: properties
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	
	private var parser: SyntaxParser?
	
	private var defaultAttributes: [NSAttributedStringKey: Any] = [:]
	private var currentChunkIndex: Int = 0
	
	var searchableTextView: NSTextView? { return editor }
	
	///true when we should ignore text storage delegate callbacks, such as when deleting the text prior to switching documents
	private var ignoreTextStorageNotifications = false
	
//	var currentFontDescriptor: NSFontDescriptor { return context!.editorFont.value.fontDescriptor }

//	var currentFontDescriptor: NSFontDescriptor = NSFont.userFixedPitchFont(ofSize: UserDefaults.standard[.defaultFontSize])!.fontDescriptor {
//		didSet {
//			let font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)
//			editor?.font = font
//			defaultAttributes[.font] = font
//		}
//	}
	
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
		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: document.file.fileType) { (topic) in
			return HelpController.shared.hasTopic(topic)
		}
		storage.setAttributedString(NSAttributedString(string: content, attributes: self.defaultAttributes))
		parser?.parseAndAttribute(string: storage, docType: context!.docType, inRange: storage.string.fullNSRange, makeChunks: true)
		updateSyntaxStyle(targetString: storage)
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
	
	@objc override func documentWillSave(_ notification: Notification) {
		guard let document = context?.currentDocument.value, let editor = editor, let lm = editor.layoutManager else { fatalError()}
		super.documentWillSave(notification)
		guard view.window != nil else { return }
		//save the index of the character at the top left of the text container
		let bnds = editor.enclosingScrollView!.contentView.bounds
		var partial: CGFloat = 1.0
		let idx = lm.characterIndex(for: bnds.origin, in: editor.textContainer!, fractionOfDistanceBetweenInsertionPoints: &partial)
		document.topVisibleIndex = idx
		document.editedContents = editor.string
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
extension SourceEditorController {
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
extension SourceEditorController: NSTextStorageDelegate {
	//called when text editing has ended
	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		guard !ignoreTextStorageNotifications else { return }
		ignoreTextStorageNotifications = true
		defer { ignoreTextStorageNotifications = false }
		parser?.parseAndAttribute(string: textStorage, docType: context!.docType, inRange: textStorage.string.fullNSRange, makeChunks: true)
		updateSyntaxStyle(targetString: textStorage)
	}
}

// MARK: NSTextViewDelegate methods
extension SourceEditorController: NSTextViewDelegate {
	func undoManager(for view: NSTextView) -> UndoManager? {
		if let currentDocument = context?.currentDocument.value { return currentDocument.undoManager }
		return editor?.undoManager
	}
	
	func textViewDidChangeSelection(_ notification: Notification) {
		guard let parser = parser else { return }
		currentChunkIndex = parser.indexOfChunk(inRange: editor!.selectedRange())
	}
	
	func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
		if let str = link as? String, let pieces = Optional(str.components(separatedBy: ":")), pieces.count == 2 {
			NotificationCenter.default.post(name: .displayHelpTopic, object:pieces[1], userInfo:nil)
			return true
		}
		return false
	}
}

