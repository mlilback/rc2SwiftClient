//
//  MacSessionEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


///selectors used in this file, aliased with shorter, descriptive names
private extension Selector {
	static let autoSave = #selector(SessionEditorController.autosaveCurrentDocument)
	static let fileChangedNotification = #selector(SessionEditorController.fileChanged(_:))
	static let findPanelAction = #selector(NSTextView.performFindPanelAction(_:))
	static let previousChunkAction = #selector(SessionEditorController.previousChunkAction(_:))
	static let nextChunkAction = #selector(SessionEditorController.nextChunkAction(_:))
}

class SessionEditorController: AbstractSessionViewController
{
	//MARK: properties
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton:NSButton?
	@IBOutlet var sourceButton:NSButton?
	@IBOutlet var fileNameField:NSTextField?
	
	let defaultUndoManager = UndoManager()
	var parser:SyntaxParser?
	fileprivate(set) var currentDocument:EditorDocument?
	fileprivate var openDocuments:[Int:EditorDocument] = [:]
	fileprivate var defaultAttributes:[String:AnyObject] = [:]
	fileprivate var currentChunkIndex = 0
	
	///true when we should ignore text storage delegate callbacks, such as when deleting the text prior to switching documents
	fileprivate var ignoreTextStorageNotifications = false
	
	var currentFontDescriptor: NSFontDescriptor = NSFont.userFixedPitchFont(ofSize: 14.0)!.fontDescriptor {
		didSet {
			let font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)
			editor?.font = font
			defaultAttributes[NSFontAttributeName] = font
		}
	}
	
	///allow dependency injection
	var notificationCenter:NotificationCenter? {
		willSet {
			if newValue != notificationCenter {
				notificationCenter?.removeObserver(self)
				NSWorkspace.shared().notificationCenter.removeObserver(self)
			}
		}
		didSet {
			if oldValue != notificationCenter {
				let ncenter = NotificationCenter.default
				ncenter.addObserver(self, selector: .autoSave, name: NSNotification.Name.NSApplicationDidResignActive, object: NSApp)
				ncenter.addObserver(self, selector: .autoSave, name: NSNotification.Name.NSApplicationWillTerminate, object: NSApp)
				ncenter.addObserver(self, selector: .fileChangedNotification, name: WorkspaceFileChangedNotification, object: nil)
				let nswspace = NSWorkspace.shared()
				nswspace.notificationCenter.addObserver(self, selector: .autoSave, name: NSNotification.Name.NSWorkspaceWillSleep, object: nswspace)
			}
		}
	}
	
	//MARK: init/deinit
	deinit {
		NSWorkspace.shared().notificationCenter.removeObserver(self)
		NotificationCenter.default.removeObserver(self)
	}
	
	//MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		guard editor != nil else { return }
		//try switching to Menlo instead of default monospaced font
		let fdesc = NSFontDescriptor(name: "Menlo-Regular", size: 14.0)
		if let _ =  NSFont(descriptor: fdesc, size: fdesc.pointSize)
		{
			currentFontDescriptor = fdesc
		}
		editor?.textContainer?.containerSize = NSMakeSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)
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
	
	func saveState() -> [String:AnyObject] {
		var dict = [String:AnyObject]()
		dict["font"] = NSKeyedArchiver.archivedData(withRootObject: currentFontDescriptor) as AnyObject?
		return dict
	}
	
	func restoreState(_ state:[String:AnyObject]) {
		if let fontData = state["font"] as? Data, let fontDesc = NSKeyedUnarchiver.unarchiveObject(with: fontData) {
			currentFontDescriptor = fontDesc as! NSFontDescriptor
		}
	}

	//called when file has changed in UI
	func fileSelectionChanged(_ file:File?) {
		var contents:String?
		if let theFile = file {
			if currentDocument?.file.fileId == theFile.fileId && currentDocument?.file.version == theFile.version { return } //same file
			session.fileHandler.contentsOfFile(theFile).onComplete { result in
				switch(result) {
				case .success(let val):
					contents = String(data: val!, encoding: String.Encoding.utf8)
				case .failure(let err):
					os_log("got error: %@", type:.error, err as NSError)
				}
				self.adjustDocumentForFile(file, content: contents)
			}
		}
	}
	
	//called when a file in the workspace file array has changed
	func fileChanged(_ note:Notification) {
		if (note as NSNotification).userInfo?["change"] == nil {
			os_log("got filechangenotification without a change object", type:.error)
			return
		}
		let change = (note as NSNotification).userInfo?["change"] as! WorkspaceFileChange
		//if it was a file change (content or metadata)
		if change.changeType == .change {
			if currentDocument?.file.fileId == change.newFile?.fileId && currentDocument?.file != change.newFile {
				let newFile = change.newFile!
				self.currentDocument?.updateFile(change.newFile!)
				self.fileSelectionChanged(newFile)
			} else if currentDocument?.file.fileId == change.newFile?.fileId {
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
	func saveDocumentToServer(_ document:EditorDocument) {
		//TODO: enable busy status
		session.sendSaveFileMessage(document) { (doc, err) -> Void in
			//ideally should remove busy progress added before this call
			os_log("saved to server", type:.info)
		}
	}
	
}

//MARK: Actions
extension SessionEditorController {
	@IBAction func previousChunkAction(_ sender:AnyObject) {
		guard currentChunkIndex > 0 else {
			os_log("called with invalid currentChunkIndex", type:.error);
			assertionFailure() //called for debug builds only
			return
		}
		currentChunkIndex -= 1
		adjustUIForCurrentChunk()
	}

	@IBAction func nextChunkAction(_ sender:AnyObject) {
		guard currentChunkIndex + 1 < parser!.chunks.count else {
			os_log("called with invalid currentChunkIndex", type:.error);
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
	
	@IBAction func runQuery(_ sender:AnyObject) {
		executeQuery(type:.Run)
	}
	
	@IBAction func sourceQuery(_ sender:AnyObject) {
		executeQuery(type:.Source)
	}
}

//MARK: UsesAdjustableFont
extension SessionEditorController: UsesAdjustableFont {
	func fontsEnabled() -> Bool {
		return true
	}
	
	func fontChanged(_ menuItem:NSMenuItem) {
		os_log("font changed: %@", type:.info, (menuItem.representedObject as? NSObject)!)
		guard let newNameDesc = menuItem.representedObject as? NSFontDescriptor else { return }
		let newDesc = newNameDesc.withSize(currentFontDescriptor.pointSize)
		currentFontDescriptor = newDesc
		editor?.font = NSFont(descriptor: newDesc, size: newDesc.pointSize)
	}
}

//Mark: NSUserInterfaceValidations
extension SessionEditorController: NSUserInterfaceValidations {
	func validateUserInterfaceItem(_ anItem: NSValidatedUserInterfaceItem) -> Bool {
		switch anItem.action! as Selector {
			case Selector.nextChunkAction:
				return currentChunkIndex + 1 < (parser?.chunks.count ?? 0)
			case Selector.previousChunkAction:
				return currentChunkIndex > 0
			case #selector(ManageFontMenu.adjustFontSize(_:)):
				return true
			case #selector(UsesAdjustableFont.fontChanged(_:)):
				return true
			default:
				return false
		}
	}
}

//MARK: NSTextStorageDelegate
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

//MARK: NSTextViewDelegate methods
extension SessionEditorController: NSTextViewDelegate {
	func undoManager(for view: NSTextView) -> UndoManager? {
		if currentDocument != nil { return currentDocument!.undoManager }
		return editor?.undoManager
	}
	
	func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
		if let pieces = (link as? String)?.components(separatedBy: ":") , pieces.count == 2 {
			NotificationCenter.default.post(name: Notification.Name(rawValue: Notifications.DisplayHelpTopic), object:pieces[1], userInfo:nil)
			return true
		}
		return false
	}
}

//MARK: private methods
private extension SessionEditorController {
	///adjusts the UI to mark the current chunk
	func adjustUIForCurrentChunk() {
		//for now we will move the cursor and scroll so it is visible
		let chunkRange = parser!.chunks[currentChunkIndex].parsedRange
		var desiredRange = NSMakeRange(chunkRange.location, 0)
		//adjust desired range so it advances past any newlines at start of chunk
		let str = editor!.string!
		let curIdx = str.characters.index(str.startIndex, offsetBy: desiredRange.location)
		if curIdx != str.endIndex && str.characters[curIdx] == "\n" {
			desiredRange.location += 1
		}
		editor!.setSelectedRange(desiredRange)
		editor!.scrollRangeToVisible(desiredRange)
	}
	
	///actually implements running a query
	func executeQuery(type:ExecuteType) {
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
			self.appStatus?.currentProgress = progress
		} else {
			session.executeScriptFile(currentDocument!.file.fileId, type: type)
		}
	}
	
	func adjustDocumentForFile(_ file:File?, content:String?) {
		let oldDocument = currentDocument
		let oldContents = editor!.textStorage!.string
		if let doc = oldDocument {
			//save the index of the character at the top left of the text container
			let bnds = editor!.enclosingScrollView!.contentView.bounds
			var partial:CGFloat = 1.0
			let idx = editor!.layoutManager!.characterIndex(for: bnds.origin, in: editor!.textContainer!, fractionOfDistanceBetweenInsertionPoints: &partial)
			doc.topVisibleIndex = idx
		}
		currentDocument?.willBecomeInactive(oldContents)
		if let theFile = file, let theText = content, let storage = editor?.textStorage {
			currentDocument = openDocuments[theFile.fileId]
			if currentDocument == nil {
				currentDocument = EditorDocument(file: theFile, fileHandler: session.fileHandler)
				openDocuments[theFile.fileId] = currentDocument!
			}
			currentDocument!.willBecomeActive()
			ignoreTextStorageNotifications = true
			storage.deleteCharacters(in: editor!.rangeOfAllText)
			parser = SyntaxParser.parserWithTextStorage(storage, fileType: theFile.fileType)
			ignoreTextStorageNotifications = false
			storage.setAttributedString(NSAttributedString(string: theText, attributes: defaultAttributes))
			if oldDocument?.dirty ?? false {
				let prog = oldDocument!.saveContents()
				self.appStatus?.currentProgress = prog
				prog?.rc2_addCompletionHandler() {
					self.saveDocumentToServer(oldDocument!)
				}
			}
			if currentDocument?.topVisibleIndex > 0 {
				//restore the scroll point to the saved character index
				let idx = editor!.layoutManager!.glyphIndexForCharacter(at: currentDocument!.topVisibleIndex)
				let point = editor!.layoutManager!.boundingRect(forGlyphRange: NSMakeRange(idx, 1), in: editor!.textContainer!)
				//postpone to next event loop cycle
				DispatchQueue.main.async {
					self.editor?.enclosingScrollView?.contentView.scroll(to: point.origin)
				}
			}
		} else {
			parser = nil
			currentDocument = nil
			editor?.textStorage?.deleteCharacters(in: editor!.rangeOfAllText)
		}
		adjustInterfaceForFile(file)
	}
	
	//adjust our interface based on new file
	func adjustInterfaceForFile(_ file:File?) {
		let selected = file != nil
		runButton?.isEnabled = selected
		sourceButton?.isEnabled = selected
		fileNameField?.stringValue = selected ? file!.name : ""
		editor?.isEditable = selected
		editor?.font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)
	}
	
}

