//
//  MacSessionEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import Freddy
import ReactiveSwift
import ClientCore
import Networking
import SyntaxParsing

///selectors used in this file, aliased with shorter, descriptive names
extension Selector {
	static let runQuery = #selector(SessionEditorController.runQuery(_:))
	static let sourceQuery = #selector(SessionEditorController.sourceQuery(_:))
	static let autoSave = #selector(SessionEditorController.autosaveCurrentDocument)
	static let findPanelAction = #selector(NSTextView.performFindPanelAction(_:))
	static let previousChunkAction = #selector(SessionEditorController.previousChunkAction(_:))
	static let nextChunkAction = #selector(SessionEditorController.nextChunkAction(_:))
	static let executeLine = #selector(SessionEditorController.executeCurrentLine(_:))
	static let executeCurrentChunk = #selector(SessionEditorController.executeCurrentChunk(_:))
	static let executePrevousChunks = #selector(SessionEditorController.executePreviousChunks(_:))
}

class SessionEditorController: AbstractSessionViewController, TextViewMenuDelegate
{
	// MARK: properties
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	
	var parser: SyntaxParser?
	private(set) var currentDocument: EditorDocument?
	private var openDocuments: [Int: EditorDocument] = [:]
	private var defaultAttributes: [NSAttributedStringKey: Any] = [:]
	private var currentChunkIndex = 0
	
	///true when we should ignore text storage delegate callbacks, such as when deleting the text prior to switching documents
	private var ignoreTextStorageNotifications = false
	
	static let defaultFontSize = CGFloat(14.0)
	
	var currentFontDescriptor: NSFontDescriptor = NSFont.userFixedPitchFont(ofSize: defaultFontSize)!.fontDescriptor {
		didSet {
			let font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)
			editor?.font = font
			defaultAttributes[.font] = font
		}
	}
	
	///allow dependency injection
	var notificationCenter: NotificationCenter? {
		willSet {
			if newValue != notificationCenter {
				notificationCenter?.removeObserver(self)
				NSWorkspace.shared.notificationCenter.removeObserver(self)
			}
		}
		didSet {
			if oldValue != notificationCenter {
				let ncenter = NotificationCenter.default
				ncenter.addObserver(self, selector: .autoSave, name: NSApplication.didResignActiveNotification, object: NSApp)
				ncenter.addObserver(self, selector: .autoSave, name: NSApplication.willTerminateNotification, object: NSApp)
				let nswspace = NSWorkspace.shared
				nswspace.notificationCenter.addObserver(self, selector: .autoSave, name: NSWorkspace.willSleepNotification, object: nswspace)
			}
		}
	}
	
	var currentChunk: DocumentChunk? {
		guard let parser = parser, parser.chunks.count > 0 else { return nil }
		return parser.chunks[currentChunkIndex]
	}
	
	var currentChunkHasPreviousExecutableChunks: Bool {
		guard let parser = parser, parser.executableChunks.count > 0, let curChunk = currentChunk, curChunk.isExecutable
			else { return false }
		// return true if not the first executable chunk
		return parser.executableChunks.index(of: curChunk) ?? 0 > 0
	}
	
	// MARK: init/deinit
	deinit {
		NSWorkspace.shared.notificationCenter.removeObserver(self)
		notificationCenter?.removeObserver(self)
	}
	
	// MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		guard editor != nil else { return }
		//try switching to Menlo instead of default monospaced font
		let fdesc = NSFontDescriptor(name: "Menlo-Regular", size: SessionEditorController.defaultFontSize)
		if let _ = NSFont(descriptor: fdesc, size: fdesc.pointSize)
		{
			currentFontDescriptor = fdesc
		}
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
		if nil == notificationCenter {
			notificationCenter = NotificationCenter.default
		}
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action  {
		case Selector.runQuery, Selector.sourceQuery:
			return currentDocument?.currentContents.count ?? 0 > 0
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
	
	func saveState() -> JSON {
		var dict = [String: JSON]()
		dict["font"] = .string(NSKeyedArchiver.archivedData(withRootObject: currentFontDescriptor).base64EncodedString())
		return .dictionary(dict)
	}
	
	func restoreState(_ state: JSON) {
		if let fontStr = try? state.getString(at: "font"), let fontData = Data(base64Encoded: fontStr),
			let fontDesc = NSKeyedUnarchiver.unarchiveObject(with: fontData) as? NSFontDescriptor
		{
			currentFontDescriptor = fontDesc
		}
	}
	
	override func sessionChanged() {
		session.workspace.fileChangeSignal.observe(on: UIScheduler()).observeValues { [unowned self] (values) in
			self.process(changes: values)
		}
	}

	//called when file has changed in UI
	func fileSelectionChanged(_ file: AppFile?) {
		if let theFile = file {
			if currentDocument?.file.fileId == theFile.fileId && currentDocument?.file.version == theFile.version { return } //same file
			self.adjustCurrentDocumentForFile(file)
		} else {
			currentDocument = nil
			self.adjustCurrentDocumentForFile(nil)
		}
	}
	
	//called when a file in the workspace file array has changed
	func process(changes: [AppWorkspace.FileChange]) {
		//if it was a file change (content or metadata)
		guard let change = changes.first(where: { $0.file.fileId == currentDocument?.file.fileId }) else { return }
		if change.type == .modify {
			guard currentDocument?.file.fileId == change.file.fileId else { return }
			self.currentDocument?.updateFile(change.file)
			self.adjustCurrentDocumentForFile(change.file)
		} else if change.type == .remove {
			//document being editied was removed
			fileSelectionChanged(nil)
		}
	}
	
	@objc func autosaveCurrentDocument() {
		guard currentDocument?.dirty ?? false else { return }
		saveWithProgress(isAutoSave: true).startWithResult { result in
			guard result.error == nil else {
				os_log("autosave failed: %{public}@", log: .session, result.error!.localizedDescription)
				return
			}
			//need to do anything when successful?
		}
	}
}

// MARK: Actions
extension SessionEditorController {
	@IBAction func previousChunkAction(_ sender: AnyObject) {
		guard currentChunkIndex > 0 else {
			os_log("called with invalid currentChunkIndex", log: .app, type: .error)
			assertionFailure() //called for debug builds only
			return
		}
		currentChunkIndex -= 1
		adjustUIForCurrentChunk()
	}

	@IBAction func nextChunkAction(_ sender: AnyObject) {
		guard currentChunkIndex + 1 < parser!.chunks.count else {
			os_log("called with invalid currentChunkIndex", log: .app, type: .error)
			assertionFailure() //called for debug builds only
			return
		}
		currentChunkIndex += 1
		adjustUIForCurrentChunk()
	}

	@IBAction override func performTextFinderAction(_ sender: Any?) {
		let menuItem = NSMenuItem(title: "foo", action: .findPanelAction, keyEquivalent: "")
		menuItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
		editor?.performFindPanelAction(menuItem)
	}
	
	@IBAction func runQuery(_ sender: AnyObject?) {
		executeQuery(type: .run)
	}
	
	@IBAction func sourceQuery(_ sender: AnyObject?) {
		executeQuery(type: .source)
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

// MARK: UsesAdjustableFont
extension SessionEditorController: UsesAdjustableFont {
	func fontsEnabled() -> Bool {
		return true
	}
	
	func fontChanged(_ menuItem: NSMenuItem) {
		os_log("font changed: %{public}@", log: .app, type: .info, (menuItem.representedObject as? NSObject)!)
		guard let newNameDesc = menuItem.representedObject as? NSFontDescriptor else { return }
		let newDesc = newNameDesc.withSize(currentFontDescriptor.pointSize)
		currentFontDescriptor = newDesc
		editor?.font = NSFont(descriptor: newDesc, size: newDesc.pointSize)
	}
}

// MARK: NSTextStorageDelegate
extension SessionEditorController: NSTextStorageDelegate {
	//called when text editing has ended
	func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		guard !ignoreTextStorageNotifications else { return }
		//we don't care if attributes changed
		guard editedMask.contains(.editedCharacters) else { return }
		guard parser != nil else { return }
		//parse() return true if the chunks changed. in that case, we need to recolor all of them
		if parser!.parse() {
			parser!.colorChunks(parser!.chunks)
		} else {
			//only color chunks in the edited range
			parser!.colorChunks(parser!.chunksForRange(editedRange))
		}
		currentChunkIndex = parser!.indexOfChunkForRange(range: editedRange)
		if currentDocument?.editedContents != textStorage.string {
			currentDocument?.editedContents = textStorage.string
		}
	}
}

// MARK: NSTextViewDelegate methods
extension SessionEditorController: NSTextViewDelegate {
	func undoManager(for view: NSTextView) -> UndoManager? {
		if currentDocument != nil { return currentDocument!.undoManager }
		return editor?.undoManager
	}
	
	func textViewDidChangeSelection(_ notification: Notification) {
		guard let parser = parser else { return }
		currentChunkIndex = parser.indexOfChunkForRange(range: editor!.selectedRange())
	}
	
	func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
		if let str = link as? String, let pieces = Optional(str.components(separatedBy: ":")), pieces.count == 2 {
			NotificationCenter.default.post(name: .DisplayHelpTopic, object:pieces[1], userInfo:nil)
			return true
		}
		return false
	}
}

// MARK: private methods
fileprivate extension SessionEditorController {
	///adjusts the UI to mark the current chunk
	func adjustUIForCurrentChunk() {
		//for now we will move the cursor and scroll so it is visible
		let chunkRange = parser!.chunks[currentChunkIndex].parsedRange
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
	
	///actually implements running a query, saving first if document is dirty
	func executeQuery(type: ExecuteType) {
		guard let currentDocument = currentDocument else {
			fatalError("runQuery called with no file selected")
		}
		let file = currentDocument.file
		guard currentDocument.dirty else {
			os_log("executeQuery executing without save", log: .app, type: .debug)
			session.execute(file: file, type: type)
			return
		}
		saveWithProgress().startWithResult { result in
			guard nil == result.error else {
				//TODO: display error or updateProgress should
				os_log("save for execute returned an error: %{public}@", log: .app, type: .info, result.error! as NSError)
				return
			}
			os_log("executeQuery saved file, now executing", log: .app, type: .info)
			self.session.execute(file: file, type: type)
		}
	}
	
	//should be the only place an actual save is performed
	private func saveWithProgress(isAutoSave: Bool = false) -> SignalProducer<Bool, Rc2Error> {
		guard let doc = currentDocument, let file = currentDocument?.file else {
			return SignalProducer<Bool, Rc2Error>(error: Rc2Error(type: .logic, severity: .error, explanation: "save called with nothing to save"))
		}
		return doc.saveContents(isAutoSave: isAutoSave)
			.flatMap(.concat, { self.session.sendSaveFileMessage(file: file, contents: $0) })
			.updateProgress(status: self.appStatus!, actionName: "Save document")
			.observe(on: UIScheduler())
	}
	
	func adjustCurrentDocumentForFile(_ file: AppFile?) {
		let editor = self.editor!
		//save old document
		if let oldDocument = currentDocument, oldDocument.file.fileId != file?.fileId {
			saveDocument(oldDocument, contents: editor.textStorage!.string)
		}
		guard let theFile = file else {
			parser = nil
			currentDocument = nil
			editor.textStorage?.deleteCharacters(in: editor.rangeOfAllText)
			updateUIForCurrentDocument()
			return
		}
		currentDocument = openDocuments[theFile.fileId]
		if currentDocument == nil {
			currentDocument = EditorDocument(file: theFile, fileCache: session.fileCache)
			openDocuments[theFile.fileId] = currentDocument!
		}
		let doc = currentDocument!
		doc.loadContents().observe(on: UIScheduler()).startWithResult { result in
			guard let contents = result.value else {
				//TODO: handle error
				os_log("error loading document contents %{public}@", log: .app, type: .error, result.error!.localizedDescription)
				return
			}
			self.documentContentsLoaded(doc, content: contents)
		}
	}
	
	func documentContentsLoaded(_ doc: EditorDocument, content: String) {
		let editor = self.editor!
		let lm = editor.layoutManager!
		doc.willBecomeActive()
		let storage = editor.textStorage!
		self.ignoreTextStorageNotifications = true
		storage.deleteCharacters(in: editor.rangeOfAllText)
		self.parser = SyntaxParser.parserWithTextStorage(storage, fileType: doc.file.fileType) { (topic) in
			return HelpController.shared.hasTopic(topic)
		}
		self.ignoreTextStorageNotifications = false
		storage.setAttributedString(NSAttributedString(string: content, attributes: self.defaultAttributes))
		if doc.topVisibleIndex > 0 {
			//restore the scroll point to the saved character index
			let idx = lm.glyphIndexForCharacter(at: doc.topVisibleIndex)
			let point = lm.boundingRect(forGlyphRange: NSRange(location: idx, length: 1), in: editor.textContainer!)
			//postpone to next event loop cycle
			DispatchQueue.main.async {
				editor.enclosingScrollView?.contentView.scroll(to: point.origin)
			}
		}
		self.updateUIForCurrentDocument()
	}
	
	func saveDocument(_ doc: EditorDocument, contents: String) {
		let editor = self.editor!
		let lm = editor.layoutManager!
		//save the index of the character at the top left of the text container
		let bnds = editor.enclosingScrollView!.contentView.bounds
		var partial: CGFloat = 1.0
		let idx = lm.characterIndex(for: bnds.origin, in: editor.textContainer!, fractionOfDistanceBetweenInsertionPoints: &partial)
		doc.topVisibleIndex = idx
		doc.willBecomeInactive(contents)
		if doc.dirty {
			saveWithProgress().startWithResult { result in
				guard nil == result.error else {
					//TODO: handle error
					os_log("editor save returned an error: %{public}@", log: .app, result.error! as NSError)
					return
				}
			}
		}
	}
	
	func updateUIForCurrentDocument() {
		let selected = currentDocument?.file != nil
		runButton?.isEnabled = selected
		sourceButton?.isEnabled = selected
		fileNameField?.stringValue = selected ? currentDocument!.file.name : ""
		editor?.isEditable = selected
		editor?.font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)
	}
}
