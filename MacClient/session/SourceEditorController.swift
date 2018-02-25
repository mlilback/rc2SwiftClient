//
//  MacSessionEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import Freddy
import ReactiveSwift
import ClientCore
import Networking
import SyntaxParsing

///selectors used in this file, aliased with shorter, descriptive names
extension Selector {
	static let runQuery = #selector(SourceEditorController.runQuery(_:))
	static let sourceQuery = #selector(SourceEditorController.sourceQuery(_:))
	static let autoSave = #selector(SourceEditorController.autosaveCurrentDocument)
	static let findPanelAction = #selector(NSTextView.performFindPanelAction(_:))
	static let previousChunkAction = #selector(SourceEditorController.previousChunkAction(_:))
	static let nextChunkAction = #selector(SourceEditorController.nextChunkAction(_:))
	static let executeLine = #selector(SourceEditorController.executeCurrentLine(_:))
	static let executeCurrentChunk = #selector(SourceEditorController.executeCurrentChunk(_:))
	static let executePrevousChunks = #selector(SourceEditorController.executePreviousChunks(_:))
}

class SourceEditorController: AbstractSessionViewController, TextViewMenuDelegate, CodeEditor
{
	// MARK: properties
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	
	private(set) var context: EditorContext?
	private var parser: SyntaxParser?
	
	private var defaultAttributes: [NSAttributedStringKey: Any] = [:]
	private var currentChunkIndex: Int = 0
	
	var searchableTextView: NSTextView? { return editor }
	
	///true when we should ignore text storage delegate callbacks, such as when deleting the text prior to switching documents
	private var ignoreTextStorageNotifications = false
	
	@objc dynamic var canExecute: Bool {
		guard context?.currentDocument.value?.isLoaded ?? false else { return false }
		return context?.currentDocument.value?.currentContents?.count ?? 0 > 0
	}
	
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
	
	// MARK: init/deinit
	deinit {
		context?.workspaceNotificationCenter.removeObserver(self)
		context?.notificationCenter.removeObserver(self)
	}
	
	// MARK: methods
	func setContext(context: EditorContext) {
		precondition(self.context == nil)
		self.context = context
		let ncenter = context.notificationCenter
		ncenter.addObserver(self, selector: .autoSave, name: NSApplication.didResignActiveNotification, object: NSApp)
		ncenter.addObserver(self, selector: .autoSave, name: NSApplication.willTerminateNotification, object: NSApp)
		ncenter.addObserver(self, selector: #selector(documentWillSave(_:)), name: .willSaveDocument, object: nil)
		context.workspaceNotificationCenter.addObserver(self, selector: .autoSave, name: NSWorkspace.willSleepNotification, object: context.workspaceNotificationCenter)
		context.editorFont.signal.observeValues { [weak self] newFont in
			self?.editor?.font = newFont
		}
		context.currentDocument.signal.observeValues { [weak self] newDoc in
			self?.documentChanged(newDocument: newDoc)
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		guard editor != nil else { return }
		editor?.menuDelegate = self
		editor?.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		editor?.textContainer?.widthTracksTextView = true
		editor?.isHorizontallyResizable = true
		editor?.isAutomaticSpellingCorrectionEnabled = false
		editor?.isEditable = false
		fileNameField?.stringValue = ""
		editor?.textStorage?.delegate = self
		let lnv = NoodleLineNumberView(scrollView: editor!.enclosingScrollView)
		editor!.enclosingScrollView!.verticalRulerView = lnv
		editor!.enclosingScrollView!.rulersVisible = true
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action  {
		case Selector.runQuery, Selector.sourceQuery:
			return context?.currentDocument.value?.currentContents?.count ?? 0 > 0
		case Selector.executeCurrentChunk:
			return currentChunk?.isExecutable ?? false
		case Selector.executePrevousChunks:
			return currentChunkHasPreviousExecutableChunks
		case Selector.executeLine:
			if editor?.selectedRange().length ?? 0 > 0 {
				menuItem.title = NSLocalizedString("Execute Selection", comment: "")
			} else {
				menuItem.title = NSLocalizedString("Execute Line", comment: "")
			}
			return editor?.string.count ?? 0 > 0
		default:
			return validateUserInterfaceItem(menuItem)
		}
	}

	func validateUserInterfaceItem(_ anItem: NSValidatedUserInterfaceItem) -> Bool {
		switch anItem.action! as Selector {
		case Selector.nextChunkAction:
			return currentChunkIndex + 1 < (parser?.chunks.count ?? 0)
		case Selector.previousChunkAction:
			return currentChunkIndex > 0
		case Selector.executePrevousChunks:
			return currentChunkHasPreviousExecutableChunks
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
	
	@objc func autosaveCurrentDocument() {
		guard context?.currentDocument.value?.isDirty ?? false else { return }
		saveWithProgress(isAutoSave: true).startWithResult { result in
			guard result.error == nil else {
				Log.warn("autosave failed: \(result.error!)", .session)
				return
			}
			//need to do anything when successful?
		}
	}

	///actually implements running a query, saving first if document is dirty
	func executeSource(type: ExecuteType) {
		guard let currentDocument = context?.currentDocument.value else {
			fatalError("runQuery called with no file selected")
		}
		let file = currentDocument.file
		guard currentDocument.isDirty else {
			Log.debug("executeQuery executing without save", .app)
			session.execute(file: file, type: type)
			return
		}
		saveWithProgress().startWithResult { result in
			if let innerError = result.error {
				let appError = AppError(.saveFailed, nestedError: innerError)
				Log.info("save for execute returned an error: \(result.error!)", .app)
				self.appStatus?.presentError(appError.rc2Error, session: self.session)
				return
			}
			Log.info("executeQuery saved file, now executing", .app)
			self.session.execute(file: file, type: type)
		}
	}
}

// MARK: Actions
extension SourceEditorController {
	@IBAction func previousChunkAction(_ sender: AnyObject) {
		guard currentChunkIndex > 0 else {
			Log.error("called with invalid currentChunkIndex", .app)
			assertionFailure() //called for debug builds only
			return
		}
		currentChunkIndex -= 1
		adjustUIForCurrentChunk()
	}

	@IBAction func nextChunkAction(_ sender: AnyObject) {
		guard let parser = parser else { fatalError() }
		let nextIndex = currentChunkIndex + 1
		guard nextIndex < parser.chunks.count else {
			Log.error("called with invalid currentChunkIndex", .app)
			assertionFailure() //called for debug builds only
			return
		}
		currentChunkIndex += 1
		adjustUIForCurrentChunk()
	}

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
	
	@IBAction func runQuery(_ sender: AnyObject?) {
		executeSource(type: .run)
	}
	
	@IBAction func sourceQuery(_ sender: AnyObject?) {
		executeSource(type: .source)
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
	
	/// Execute every code chunk up to, but not including, the current chunk
	@IBAction func executePreviousChunks(_ sender: Any?) {
		guard let parser = parser, let editor = editor else { fatalError("why is there no parser?") }
		let chunkNumber = currentChunk?.chunkNumber ?? 0
		let fullScript = editor.textStorage!.mutableString as String //string makes a copy, we only need reference
		let validChunks = parser.executableChunks.prefix(while: { $0.chunkNumber < chunkNumber })
		validChunks.forEach({ self.session.executeScript($0.executableCode(from: fullScript)) })
	}
	
	@IBAction func executeCurrentChunk(_ sender: Any?) {
		guard let chunk = currentChunk, chunk.isExecutable,
			let fullScript = editor?.textStorage?.mutableString as String? //string makes a copy, we only need reference
			else { return }
		session.executeScript(chunk.executableCode(from: fullScript))
	}
}

// MARK: NSTextStorageDelegate
extension SourceEditorController: NSTextStorageDelegate {
	//called when text editing has ended
	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		guard !ignoreTextStorageNotifications else { return }
		guard let parser = parser else { fatalError("no parser when text changed") }
		//we don't care if attributes changed
		guard editedMask.contains(.editedCharacters) else { return }
		//parse() return true if the chunks changed. in that case, we need to recolor all of them
		if parser.parse() {
			parser.colorChunks(parser.chunks)
		} else {
			//only color chunks in the edited range
			parser.colorChunks(parser.chunksForRange(editedRange))
		}
		let currentDocument = context?.currentDocument.value
		currentChunkIndex = parser.indexOfChunk(range: editedRange)
		if currentDocument?.editedContents != textStorage.string {
			currentDocument?.editedContents = textStorage.string
		}
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
		currentChunkIndex = parser.indexOfChunk(range: editor!.selectedRange())
	}
	
	func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
		if let str = link as? String, let pieces = Optional(str.components(separatedBy: ":")), pieces.count == 2 {
			NotificationCenter.default.post(name: .displayHelpTopic, object:pieces[1], userInfo:nil)
			return true
		}
		return false
	}
}

// MARK: private methods
fileprivate extension SourceEditorController {
	///adjusts the UI to mark the current chunk
	func adjustUIForCurrentChunk() {
		guard let parser = parser else { fatalError("called without parser") }
		//for now we will move the cursor and scroll so it is visible
		let chunkRange = parser.chunks[currentChunkIndex].parsedRange
		var desiredRange = NSRange(location: chunkRange.location, length: 0)
		//adjust desired range so it advances past any newlines at start of chunk (if not just whitespace)
		let str = editor!.string
		//only adjust if it includes a non-newline character
		if let nlcount = str.substring(from: desiredRange)?.unicodeScalars.filter({ CharacterSet.newlines.contains($0) }), nlcount.count != chunkRange.length
		{
			let curIdx = str.index(str.startIndex, offsetBy: desiredRange.location)
			if curIdx != str.endIndex && str[curIdx] == "\n" {
				desiredRange.location += 1
			}
		}
		editor!.setSelectedRange(desiredRange)
		editor!.scrollRangeToVisible(desiredRange)
	}
	
	//should be the only place an actual save is performed
	private func saveWithProgress(isAutoSave: Bool = false) -> SignalProducer<Bool, Rc2Error> {
		guard let context = context else { fatalError() }
		guard let doc = context.currentDocument.value else {
			return SignalProducer<Bool, Rc2Error>(error: Rc2Error(type: .logic, severity: .error, explanation: "save called with nothing to save"))
		}
		return context.save(document: doc, isAutoSave: isAutoSave)
			.map { _ in return true }
			.updateProgress(status: self.appStatus!, actionName: "Save document")
			.observe(on: UIScheduler())
	}
	
	func documentChanged(newDocument: EditorDocument?) {
		guard let editor = self.editor else { Log.error("can't adjust document without editor", .app); return }
		if let document = newDocument {
			if document.isLoaded {
				loaded(document: document, content: document.currentContents ?? "")
			} else {
				session.fileCache.contents(of: document.file).observe(on: UIScheduler()).startWithResult { result in
					guard let data = result.value else  {
						self.appStatus?.presentError(result.error!, session: self.session)
						return
					}
					self.loaded(document: document, content: String(data: data, encoding: .utf8)!)
				}
			}
		} else {
			editor.textStorage?.deleteCharacters(in: editor.rangeOfAllText)
		}
		updateUIForCurrentDocument()
	}
	
	func loaded(document: EditorDocument, content: String) {
		guard let editor = self.editor, let lm = editor.layoutManager, let storage = editor.textStorage, let txtContainer = editor.textContainer
		else { fatalError("editor missing required pieces") }
		ignoreTextStorageNotifications = true
		storage.deleteCharacters(in: editor.rangeOfAllText)
		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: document.file.fileType) { (topic) in
			return HelpController.shared.hasTopic(topic)
		}
		ignoreTextStorageNotifications = false
		storage.setAttributedString(NSAttributedString(string: content, attributes: self.defaultAttributes))
		if document.topVisibleIndex > 0 {
			//restore the scroll point to the saved character index
			let idx = lm.glyphIndexForCharacter(at: document.topVisibleIndex)
			let point = lm.boundingRect(forGlyphRange: NSRange(location: idx, length: 1), in: txtContainer)
			//postpone to next event loop cycle
			DispatchQueue.main.async {
				editor.enclosingScrollView?.contentView.scroll(to: point.origin)
			}
		}
		self.updateUIForCurrentDocument()
	}
	
	@objc func documentWillSave(_ notification: Notification) {
		guard let document = context?.currentDocument.value, let editor = editor, let lm = editor.layoutManager else { fatalError()}
		//save the index of the character at the top left of the text container
		let bnds = editor.enclosingScrollView!.contentView.bounds
		var partial: CGFloat = 1.0
		let idx = lm.characterIndex(for: bnds.origin, in: editor.textContainer!, fractionOfDistanceBetweenInsertionPoints: &partial)
		document.topVisibleIndex = idx
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
