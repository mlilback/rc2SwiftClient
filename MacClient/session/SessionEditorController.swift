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
	
	var currentFile:File?
	var parser:SyntaxParser?
	
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
			return currentFile != nil
		}
		return super.validateMenuItem(menuItem)
	}
	
	@IBAction func runQuery(sender:AnyObject) {
		assert(currentFile != nil, "runQuery called with no file selected")
		session.executeScriptFile((currentFile?.fileId)!)
	}

	@IBAction func sourceQuery(sender:AnyObject) {
		//TODO: implement sourcing files
		assert(currentFile != nil, "runQuery called with no file selected")
		session.executeScriptFile((currentFile?.fileId)!)
	}

	func fileSelectionChanged(newFile:File?, text:String?) {
		let selected = newFile != nil
		if let theText = text {
			parser = SyntaxParser.parserWithTextStorage(editor!.textStorage!, fileType: newFile!.fileType)
			editor?.string = theText
		} else {
			//disable editor
			editor?.editable = false
			editor?.textStorage?.deleteCharactersInRange(NSMakeRange(0, (editor?.textStorage!.length)!))
			parser = nil
		}
		currentFile = newFile
		runButton?.enabled = selected
		sourceButton?.enabled = selected
		fileNameField?.stringValue = selected ? (currentFile?.name)! : ""
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
}

