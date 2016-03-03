//
//  MacSessionEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class SessionEditorController: AbstractSessionViewController, NSTextViewDelegate, NSTextStorageDelegate {
	@IBOutlet var editor: SessionEditor?
	@IBOutlet var runButton:NSButton?
	@IBOutlet var sourceButton:NSButton?
	@IBOutlet var fileNameField:NSTextField?
	
	let defaultUndoManager = NSUndoManager()
	var parser:SyntaxParser?
	private(set) var currentDocument:EditorDocument?
	private var openDocuments:[Int:EditorDocument] = [:]
	
	@IBAction override func performTextFinderAction(sender: AnyObject?) {
		let menuItem = NSMenuItem(title: "foo", action: Selector("performFindPanelAction:"), keyEquivalent: "")
		menuItem.tag = Int(NSFindPanelAction.ShowFindPanel.rawValue)
		editor?.performFindPanelAction(menuItem)
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
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
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		if menuItem.action == "runQuery:" {
			print("setting run enabled state")
			return currentDocument != nil
		}
		return super.validateMenuItem(menuItem)
	}
	
	@IBAction func runQuery(sender:AnyObject) {
		assert(currentDocument != nil, "runQuery called with no file selected")
		session.executeScriptFile(currentDocument!.file.fileId)
	}

	@IBAction func sourceQuery(sender:AnyObject) {
		//TODO: implement sourcing files
		assert(currentDocument != nil, "runQuery called with no file selected")
		session.executeScriptFile(currentDocument!.file.fileId)
	}

	//called when file has changed in UI
	func fileSelectionChanged(file:File?) {
		var contents:String?
		if let theFile = file {
			if currentDocument?.file.fileId == theFile.fileId { return } //same file
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
				appStatus?.updateStatus(oldDocument!.saveContents())
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
	}
	
	//MARK: NSTextViewDelegate methods
	func undoManagerForTextView(view: NSTextView) -> NSUndoManager? {
		if currentDocument != nil { return currentDocument!.undoManager }
		return editor?.undoManager
	}
}

