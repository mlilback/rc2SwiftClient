//
//  MacSessionOutputController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MacSessionOutputController: AbstractSessionViewController {
	@IBOutlet var consoleTextField: ConsoleTextField?
	@IBOutlet var historyButton: NSButton?
	let historyMenu = NSMenu()
	var commandHistory = [String]()
	dynamic var consoleInputText = "" { didSet { canExecute = consoleInputText.characters.count > 0 } }
	dynamic var canExecute = false
	
	override func awakeFromNib() {
		super.awakeFromNib()
		//add some dummy data for now
		if commandHistory.count == 0 {
			commandHistory.append("y <- c(1,2,3)")
			commandHistory.append("rnorm(11)")
		}
	}
	
	override func viewDidLoad() {
		consoleTextField?.adjustContextualMenu = { (editor:NSText, theMenu:NSMenu) in
			return theMenu
		}
	}
	
	@IBAction func historyClicked(sender:AnyObject?) {
		adjustCommandHistoryMenu()
		let hframe = historyButton?.superview?.convertRect((historyButton?.frame)!, toView: nil)
		let rect = view.window?.convertRectToScreen(hframe!)
		print("historybutton\(rect)")
		historyMenu.popUpMenuPositioningItem(nil, atLocation: (rect?.origin)!, inView: nil)
	}

	@IBAction func displayHistoryItem(sender:AnyObject?) {
		let mi = sender as! NSMenuItem
		consoleInputText = mi.representedObject as! String
		canExecute = consoleInputText.characters.count > 0
		view.window?.makeFirstResponder(consoleTextField)
	}
	
	func adjustCommandHistoryMenu() {
		historyMenu.removeAllItems()
		for aCommand in commandHistory {
			var menuCommand = aCommand
			if aCommand.characters.count > 50 {
				menuCommand = menuCommand.substringToIndex(menuCommand.startIndex.advancedBy(49)).stringByAppendingString("…")
			}
			let menuItem = NSMenuItem(title: menuCommand, action: "displayHistoryItem:", keyEquivalent: "")
			menuItem.target = self
			menuItem.representedObject = aCommand //store full command in case cropped above
			historyMenu.addItem(menuItem)
		}
	}
}

