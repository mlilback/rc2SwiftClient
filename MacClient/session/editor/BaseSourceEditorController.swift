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
import ClientCore
import Parsing

/// pfrotocol to allow setting the font of something without knowing anything else about it.
protocol FontUser {
	var font: NSFont { get set }
}

class BaseSourceEditorController: AbstractEditorController, TextViewMenuDelegate
{
	// MARK: properties
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	
	// used so observations are removed when deallocated
	private let (_editorLifetime, _editorToken) = Lifetime.make()
	var editorLifetime: Lifetime { return _editorLifetime }
	
	var parser: Rc2RmdParser?
	var useParser = false
	
	var defaultAttributes: [NSAttributedString.Key: Any] = [:]
//	var currentChunkIndex: Int = 0
	var fontUser: FontUser?

	var searchableTextView: NSTextView? { return editor }
	
	/// true when we should ignore text storage delegate callbacks, such as when deleting the text prior to switching documents
	var ignoreTextStorageNotifications = false
	
//	var currentChunk: RmdDocumentChunk? {
//		guard let parser = self.parser, parser.children.count > 0 else { return nil }
//		return parser.chunks[currentChunkIndex]
//	}
	
	override var documentDirty: Bool {
		guard let edited = editor?.string, let original = context?.currentDocument.value?.savedContents else { return false }
		return edited != original
	}
	
	// MARK: - init/deinit
	deinit {
		context?.workspaceNotificationCenter.removeObserver(self)
		context?.notificationCenter.removeObserver(self)
	}
	
	// MARK: methods
	override func setContext(context: EditorContext) {
		super.setContext(context: context)
		context.editorFont.signal.observeValues { [weak self] newFont in
			self?.fontChanged(newFont)
		}
	}
	
	func fontChanged(_ newFont: NSFont) {
		editor?.font = newFont
		fontUser?.font = newFont
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		guard let editor = editor, let storage = editor.textStorage else { return }
		editor.menuDelegate = self
		fileNameField?.stringValue = ""
		storage.delegate = self
		fontUser = editor.enableLineNumberView(ignoreHandler: { [weak self] in self?.ignoreTextStorageNotifications ?? false })
		if let currentFont = context?.editorFont.value {
			fontUser?.font = currentFont
		}
		editor.textContainer?.replaceLayoutManager(SourceEditorLayoutManager())
		editor.enclosingScrollView?.rulersVisible = true
		// adjust link color when theme changes
		ThemeManager.shared.activeSyntaxTheme.signal.take(during: editorLifetime).observeValues { [weak self] _ in self?.adjustLinkColor() }
		adjustLinkColor()
		// even if not using parser, need it for syntax highlighting
		parser = Rc2RmdParser(contents: storage, help: { (topic) -> Bool in
			HelpController.shared.hasTopic(topic) })
		if useParser, storage.length > 0 {
			do {
				try parser?.reparse()
			} catch {
				Log.warn("error during initial parse: \(error)", .parser)
			}
		}
	}
	
	@objc override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
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
	
	// MARK: - private methods
	
	override func documentChanged(newDocument: EditorDocument?) {
		guard let editor = self.editor else { Log.error("can't adjust document without editor", .app); return }
		super.documentChanged(newDocument: newDocument)
		if nil == newDocument {
			editor.textStorage?.deleteCharacters(in: editor.rangeOfAllText)
			fileNameField?.stringValue = ""
		}
		updateUIForCurrentDocument()
	}
	
	override func loaded(content: String) {
		guard let editor = self.editor, let lm = editor.layoutManager, let storage = editor.textStorage, let txtContainer = editor.textContainer, let document = context!.currentDocument.value
			else { fatalError("editor missing required pieces") }
		ignoreTextStorageNotifications = true
		let origCursorRange = editor.selectedRange()
		storage.deleteCharacters(in: editor.rangeOfAllText)
		storage.setAttributedString(NSAttributedString(string: content, attributes: self.defaultAttributes))
		let range = storage.string.fullNSRange
		if isRDocument {
			parser?.highlight(text: storage, range: range)
			colorizeHighlightAttributes()
		} else if context?.currentDocument.value?.isRmarkdown ?? false {
			do {
				try parser?.reparse()
			} catch {
				Log.warn("failed to parse rmd \(error)", .app)
			}
		}
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
		// restore selection/cursor to same point
		if origCursorRange.upperBound < storage.length {
			// TODO: does this take into account how much was added/deleted before the cursor (via paste?) and adjust location so the same selection is there? Seems like it does, but need to confirm in solid testing.
			editor.setSelectedRange(origCursorRange)
		}
		onDocumentLoaded?(document)
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
		if document.isDirty {
			save(edits: editor.string)
		}
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
	
	
	/// Called when the contents of the editor have changed due to user action. Should be orverriden to parse and highlight the changed contents
	///
	/// - Parameters:
	///   - contents: The contents of the editor that was changed
	///   - range: the range of the original text that changed
	///   - delta: the length delta for the edited change
	func contentsChanged(_ contents: NSTextStorage, range: NSRange, changeLength delta: Int) {
	}
	
	
	func adjustLinkColor() {
//		let theme = ThemeManager.shared.activeSyntaxTheme.value
//		var dict = [NSAttributedString.Key: Any]()
//		dict[.foregroundColor] = theme.color(for: .keyword)
//		editor?.linkTextAttributes = dict
	}
	
	/// updates the style attributes for a fragment in an attributed string
	func style(fragmentType: SyntaxElement, in text: NSMutableAttributedString, range: NSRange, theme: SyntaxTheme, skipLinks: Bool = false) {
		switch fragmentType {
		case .string:
			text.addAttribute(.foregroundColor, value: theme.color(for: .quote), range: range)
		case .comment:
			text.addAttribute(.foregroundColor, value: theme.color(for: .comment), range: range)
		case .number:
			text.addAttribute(.foregroundColor, value: theme.color(for: .symbol), range: range)
		case .symbol:
			text.addAttribute(.foregroundColor, value: theme.color(for: .keyword), range: range)
		case .functonName:
//			text.addAttribute(.foregroundColor, value: theme.color(for: .function), range: range)
			let funName = text.attributedSubstring(from: range).string
			if !skipLinks && HelpController.shared.hasTopic(funName) {
				text.addAttribute(.link, value: "help:\(funName)", range: range)
			} else {
				text.addAttribute(.foregroundColor, value: theme.color(for: .function), range: range)
			}
		}
	}
	
	/// Changes any SyntaxElement tags the appropriate style
	/// - Parameter range: The range to change, defaults to all.
	func colorizeHighlightAttributes(range: NSRange? = nil) {
//		Log.info("colorizing preview editor", .app)
		guard let edit = editor, let storage = edit.textStorage else { return }
		let rng = range ?? NSRange(location: 0, length: storage.length)
		// adjust document font
		storage.removeAttribute(.font, range: storage.string.fullNSRange)
		storage.addAttribute(.font, value: context!.editorFont.value, range: storage.string.fullNSRange)

		let theme = ThemeManager.shared.activeSyntaxTheme.value
		storage.removeAttribute(.foregroundColor, range: rng)
		storage.removeAttribute(.backgroundColor, range: rng)
		storage.enumerateAttributes(in: rng, options: []) { (keyValues, attrRange, stop) in
			if let fragmentType = keyValues[SyntaxKey] as? SyntaxElement {
				// skip links if it an equation
				var skip = false
				var effRange: NSRange = NSRange()
				if let ctype = storage.attribute(ChunkKey, at: attrRange.location, longestEffectiveRange: &effRange, in: rng) as? ChunkType {
					skip = ctype == .equation || ctype == .inlineEquation
				}
				self.style(fragmentType: fragmentType, in: storage, range: attrRange, theme: theme, skipLinks: skip)
			}
		}
	}
}

// MARK: - Actions
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
	@IBAction func executeCurrentLine(_ sender: Any?) {
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

// MARK: - NSTextStorageDelegate
extension BaseSourceEditorController: NSTextStorageDelegate {
	//called when text editing has ended
	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		guard delta != 0 else { return } // only count as change if the text changed
//		guard isRDocument else { return }
		guard !ignoreTextStorageNotifications else { return }
		ignoreTextStorageNotifications = true
		defer { ignoreTextStorageNotifications = false }
		contentsChanged(textStorage, range: editedRange, changeLength: delta)
	}
}

// MARK: - NSTextViewDelegate methods
extension BaseSourceEditorController: NSTextViewDelegate {
	func undoManager(for view: NSTextView) -> UndoManager? {
		if let currentDocument = context?.currentDocument.value {
			return currentDocument.undoManager
		}
		return nil
	}
	
	// Why was this being done? Why reparse when the selection changes?
	func textViewDidChangeSelection(_ notification: Notification) {
		guard !ignoreTextStorageNotifications else { return }
//		guard let editor = editor  else { fatalError("recvd selection changed with no editor") }
//		guard let parser = parser, useParser, editor.textStorage!.length > 0 else { return }
//		parser.selectionChanged(range: editor.selectedRange())
//		currentChunkIndex = parser.indexOfChunk(inRange: editor!.selectedRange())
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
