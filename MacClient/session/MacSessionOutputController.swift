//
//  MacSessionOutputController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///ViewController whose view contains the text view showing the results, and the text field for entering short queries
class MacSessionOutputController: AbstractSessionViewController, SessionOutputHandler {
	//MARK: properties
	@IBOutlet var resultsView: ResultsView?
	@IBOutlet var consoleTextField: ConsoleTextField?
	@IBOutlet var historyButton: NSButton?
	var outputFont: NSFont = NSFont(name: "Menlo", size: 14)!
	let cmdHistory: CommandHistory
	dynamic var consoleInputText = "" { didSet { canExecute = consoleInputText.characters.count > 0 } }
	dynamic var canExecute = false
	
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
	}
	
	//MARK: actions
	@IBAction func executeQuery(sender:AnyObject?) {
		guard consoleInputText.characters.count > 0 else { return }
		session.executeScript(consoleInputText)
		cmdHistory.addToCommandHistory(consoleInputText)
	}
	
	//MARK: SessionOutputHandler
	func appendFormattedString(string:NSAttributedString) {
		let mutStr = string.mutableCopy() as! NSMutableAttributedString
		mutStr.addAttributes(["NSFont":outputFont], range: NSMakeRange(0, string.length))
		resultsView!.textStorage?.appendAttributedString(mutStr)
		resultsView!.scrollToEndOfDocument(nil)
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
}
