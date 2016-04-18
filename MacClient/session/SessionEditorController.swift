//
//  MacSessionEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///selectors used in this file, aliased with shorter, descriptive names
private extension Selector {
	static let autoSave = #selector(SessionEditorController.autosaveCurrentDocument)
	static let fileChangedNotification = #selector(SessionEditorController.fileChanged(_:))
	static let findPanelAction = #selector(NSTextView.performFindPanelAction(_:))
}

class SessionEditorController: AbstractSessionViewController, NSTextViewDelegate, NSTextStorageDelegate {
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton:NSButton?
	@IBOutlet var sourceButton:NSButton?
	@IBOutlet var fileNameField:NSTextField?
	
	let defaultUndoManager = NSUndoManager()
	var parser:SyntaxParser?
	private(set) var currentDocument:EditorDocument?
	private var openDocuments:[Int:EditorDocument] = [:]
	
	///allow dependency injection
	var notificationCenter:NSNotificationCenter? {
		willSet {
			if newValue != notificationCenter {
				notificationCenter?.removeObserver(self)
				NSWorkspace.sharedWorkspace().notificationCenter.removeObserver(self)
			}
		}
		didSet {
			if oldValue != notificationCenter {
				let ncenter = NSNotificationCenter.defaultCenter()
				ncenter.addObserver(self, selector: .autoSave, name: NSApplicationDidResignActiveNotification, object: NSApp)
				ncenter.addObserver(self, selector: .autoSave, name: NSApplicationWillTerminateNotification, object: NSApp)
				ncenter.addObserver(self, selector: .fileChangedNotification, name: WorkspaceFileChangedNotification, object: nil)
				let nswspace = NSWorkspace.sharedWorkspace()
				nswspace.notificationCenter.addObserver(self, selector: .autoSave, name: NSWorkspaceWillSleepNotification, object: nswspace)
			}
		}
	}
	
	//TODO: allow DI of notification center
	deinit {
		NSWorkspace.sharedWorkspace().notificationCenter.removeObserver(self)
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
	
	@IBAction override func performTextFinderAction(sender: AnyObject?) {
		let menuItem = NSMenuItem(title: "foo", action: .findPanelAction, keyEquivalent: "")
		menuItem.tag = Int(NSFindPanelAction.ShowFindPanel.rawValue)
		editor?.performFindPanelAction(menuItem)
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		guard editor != nil else { return }
		var font:NSFont? = NSFont(name: "Menlo", size: 14.0)
		if font == nil {
			font = NSFont.userFixedPitchFontOfSize(14.0)
		}
		editor?.font = font
		editor?.textContainer?.containerSize = NSMakeSize(CGFloat.max, CGFloat.max)
		editor?.textContainer?.widthTracksTextView = true
		editor?.horizontallyResizable = true
		editor?.automaticSpellingCorrectionEnabled = false
		editor?.editable = false
		fileNameField?.stringValue = ""
		editor?.textStorage?.delegate = self
		let lnv = NoodleLineNumberView(scrollView: editor!.enclosingScrollView)
		editor!.enclosingScrollView!.verticalRulerView = lnv
		editor!.enclosingScrollView!.rulersVisible = true
		if nil == notificationCenter {
			notificationCenter = NSNotificationCenter.defaultCenter()
		}
	}
	
//	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
//		if menuItem.action == #selector(SessionEditorController.runQuery(_:)) {
//			print("setting run enabled state")
//			return currentDocument != nil
//		}
//		return super.validateMenuItem(menuItem)
//	}
	
	@IBAction func runQuery(sender:AnyObject) {
		executeQuery(type:.Run)
	}

	@IBAction func sourceQuery(sender:AnyObject) {
		executeQuery(type:.Source)
	}

	//actually implements running a query
	func executeQuery(type type:ExecuteType) {
		assert(currentDocument != nil, "runQuery called with no file selected")
		if currentDocument!.dirty {
			//not passing autosave param, so will always return progress
			let progress = currentDocument!.saveContents()
			progress!.rc2_addCompletionHandler() {
				self.session.sendSaveFileMessage(self.currentDocument!, executeType: type) {doc, error in
					//TODO notify user of error
					self.session.executeScriptFile(doc.file.fileId, type: type)
				}
			}
			appStatus?.updateStatus(progress)
		} else {
			session.executeScriptFile(currentDocument!.file.fileId, type: type)
		}
	}
	
	//called when file has changed in UI
	func fileSelectionChanged(file:File?) {
		var contents:String?
		if let theFile = file {
			if currentDocument?.file.fileId == theFile.fileId && currentDocument?.file.version == theFile.version { return } //same file
			session.fileHandler.contentsOfFile(theFile).onComplete { result in
				switch(result) {
				case .Success(let val):
					contents = String(data: val!, encoding: NSUTF8StringEncoding)
				case .Failure(let err):
					log.warning("got error \(err)")
				}
				self.adjustDocumentForFile(file, content: contents)
			}
		}
	}
	
	//called when a file in the workspace file array has changed
	func fileChanged(note:NSNotification) {
		if note.userInfo?["change"] == nil {
			log.error("got filechangenotification without a change object")
			return
		}
		let change = note.userInfo?["change"] as! WorkspaceFileChange
		//if it was a file change (content or metadata)
		if change.changeType == .Change {
			if currentDocument?.file.fileId == change.newFile?.fileId && currentDocument?.file != change.newFile {
				let newFile = change.newFile!
				self.currentDocument?.updateFile(change.newFile!)
				self.fileSelectionChanged(newFile)
			} else if currentDocument!.file.fileId == change.newFile?.fileId {
				let progress = session.fileHandler.fileCache.flushCacheForFile(change.newFile!)
				progress?.rc2_addCompletionHandler() {
					let newFile = change.newFile!
					self.currentDocument?.updateFile(change.newFile!)
					self.fileSelectionChanged(newFile)
				}
			}
		}
	}
	
	func autosaveCurrentDocument() {
		guard currentDocument?.dirty ?? false else { return }
		let prog = currentDocument!.saveContents(isAutoSave: true)
		prog?.rc2_addCompletionHandler() {
			self.saveDocumentToServer(self.currentDocument!)
		}
	}
	
	//should be called when document is locally saved but stil marked as dirty (e.g. from progress completion handler)
	func saveDocumentToServer(document:EditorDocument) {
		//TODO: enable busy status
		session.sendSaveFileMessage(document) { (doc, err) -> Void in
			//ideally should remove busy progress added before this call
			log.info("saved to server")
		}
	}
	
	private func adjustDocumentForFile(file:File?, content:String?) {
		let oldDocument = currentDocument
		let oldContents = editor!.textStorage!.string
		currentDocument?.willBecomeInactive(oldContents)
		if let theFile = file, theText = content {
			currentDocument = openDocuments[theFile.fileId]
			if currentDocument == nil {
				currentDocument = EditorDocument(file: theFile, fileHandler: session.fileHandler)
				openDocuments[theFile.fileId] = currentDocument!
			}
			currentDocument!.willBecomeActive()
			parser = SyntaxParser.parserWithTextStorage(editor!.textStorage!, fileType: theFile.fileType)
			editor!.replaceCharactersInRange(editor!.rangeOfAllText, withString: theText)
			if oldDocument?.dirty ?? false {
				let prog = oldDocument!.saveContents()
				appStatus?.updateStatus(prog)
				prog?.rc2_addCompletionHandler() {
					self.saveDocumentToServer(oldDocument!)
				}
			}
		} else {
			parser = nil
			currentDocument = nil
			editor?.textStorage?.deleteCharactersInRange(editor!.rangeOfAllText)
		}
		adjustInterfaceForFile(file)
	}
	
	//adjust our interface based on new file
	private func adjustInterfaceForFile(file:File?) {
		let selected = file != nil
		runButton?.enabled = selected
		sourceButton?.enabled = selected
		fileNameField?.stringValue = selected ? file!.name : ""
		editor?.editable = selected
	}

	//MARK: NSTextStorageDelegate methods
	//called when text editing has ended
	func textStorage(textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		//we don't care if attributes changed
		guard editedMask.contains(.EditedCharacters) else { return }
		guard parser != nil else { return }
		//parse() return true if the chunks changed. in that case, we need to recolor all of them
		if parser!.parse() {
			parser!.colorChunks(parser!.chunks)
		} else {
			//only color chunks in the edited range
			parser!.colorChunks(parser!.chunksForRange(editedRange))
		}
		if currentDocument?.editedContents != textStorage.string {
			currentDocument?.editedContents = textStorage.string
		}
	}

	//MARK: NSTextViewDelegate methods
	func undoManagerForTextView(view: NSTextView) -> NSUndoManager? {
		if currentDocument != nil { return currentDocument!.undoManager }
		return editor?.undoManager
	}
}

