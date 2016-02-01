//
//  MacSessionOutputController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

enum SessionStateKey: String {
	case History = "history"
	case Results = "results"
}

///ViewController whose view contains the text view showing the results, and the text field for entering short queries
class SessionConsoleController: AbstractSessionViewController, NSTextViewDelegate, NSTextFieldDelegate 
{
	//MARK: properties
	@IBOutlet var resultsView: ResultsView?
	@IBOutlet var consoleTextField: ConsoleTextField?
	@IBOutlet var historyButton: NSButton?
	var outputFont: NSFont = NSFont(name: "Menlo", size: 14)!
	let cmdHistory: CommandHistory
	dynamic var consoleInputText = "" { didSet { canExecute = consoleInputText.characters.count > 0 } }
	dynamic var canExecute = false
	var viewFileOrImage: ((fileWrapper: NSFileWrapper) -> ())?
	
	required init?(coder: NSCoder) {
		cmdHistory = CommandHistory(target:nil, selector:Selector("displayHistoryItem:"))
		super.init(coder: coder)
	}
	
	//MARK: overrides
	override func viewDidLoad() {
		super.viewDidLoad()
		cmdHistory.target = self
		consoleTextField?.adjustContextualMenu = { (editor:NSText, theMenu:NSMenu) in
			return theMenu
		}
		resultsView?.textContainerInset = NSMakeSize(4, 4)
	}
	
	//MARK: actions
	@IBAction func executeQuery(sender:AnyObject?) {
		guard consoleInputText.characters.count > 0 else { return }
		session.executeScript(consoleInputText)
		cmdHistory.addToCommandHistory(consoleInputText)
		consoleTextField?.stringValue = ""
	}
	
	//MARK: SessionOutputHandler
	func appendFormattedString(string:NSAttributedString) {
		let mutStr = string.mutableCopy() as! NSMutableAttributedString
		mutStr.addAttributes([NSFontAttributeName:outputFont], range: NSMakeRange(0, string.length))
		resultsView!.textStorage?.appendAttributedString(mutStr)
		resultsView!.scrollToEndOfDocument(nil)
	}
	
	func saveSessionState() -> AnyObject {
		var dict = [String:AnyObject]()
		dict[SessionStateKey.History.rawValue] = cmdHistory.commands
		dict[SessionStateKey.Results.rawValue] = resultsView?.textStorage?.RTFDFromRange(NSMakeRange(0, (resultsView?.textStorage?.length)!), documentAttributes: [NSDocumentTypeDocumentAttribute:NSRTFDTextDocumentType])
		return dict
	}

	func restoreSessionState(state:[String:AnyObject]) {
		if state[SessionStateKey.History.rawValue] is NSArray {
			cmdHistory.commands = state[SessionStateKey.History.rawValue] as! [String]
		}
		if state[SessionStateKey.Results.rawValue] is NSData {
			let data = state[SessionStateKey.Results.rawValue] as! NSData
			let ts = resultsView!.textStorage!
			resultsView!.replaceCharactersInRange(NSMakeRange(0, ts.length), withRTFD:data)
			resultsView!.textStorage?.enumerateAttribute(NSAttachmentAttributeName, inRange: NSMakeRange(0, ts.length), options: [], usingBlock:
			{ (value, range, stop) -> Void in
				guard let attach = value as? NSTextAttachment else { return }
				let fw = attach.fileWrapper
				let fname = (fw?.filename!)!
				if fname.hasPrefix("img") {
					let cell = NSTextAttachmentCell(imageCell: NSImage(named: "graph"))
					cell.image?.size = NSMakeSize(48, 48)
					ts.removeAttribute(NSAttachmentAttributeName, range: range)
					attach.attachmentCell = cell
					ts.addAttribute(NSAttachmentAttributeName, value: attach, range: range)
				} else if fname.hasPrefix("file") {
					//TODO: set cell for a file attachment
				}
			})
		}
	}
	
	//MARK: command history
	@IBAction func historyClicked(sender:AnyObject?) {
		cmdHistory.adjustCommandHistoryMenu()
		let hframe = historyButton?.superview?.convertRect((historyButton?.frame)!, toView: nil)
		let rect = view.window?.convertRectToScreen(hframe!)
		cmdHistory.historyMenu.popUpMenuPositioningItem(nil, atLocation: (rect?.origin)!, inView: nil)
	}

	@IBAction func displayHistoryItem(sender:AnyObject?) {
		let mi = sender as! NSMenuItem
		consoleInputText = mi.representedObject as! String
		canExecute = consoleInputText.characters.count > 0
		view.window?.makeFirstResponder(consoleTextField)
	}
	
	@IBAction func clearConsole(sender:AnyObject?) {
		resultsView?.textStorage?.deleteCharactersInRange(NSMakeRange(0, (resultsView?.textStorage?.length)!))
	}
	
	//MARK: textfield delegate
	func control(control: NSControl, textView: NSTextView, doCommandBySelector commandSelector: Selector) -> Bool {
		if commandSelector == "insertNewline:" {
			executeQuery(control)
			return true
		}
		return false
	}
	
	//MARK: textview delegate
	func textView(textView: NSTextView, clickedOnCell cell: NSTextAttachmentCellProtocol, inRect cellFrame: NSRect, atIndex charIndex: Int)
	{
		let attach = cell.attachment
		guard let fw = attach?.fileWrapper else { return }
		viewFileOrImage?(fileWrapper: fw)
	}
}

