//
//  CommandHistory.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let MinHistoryLength = 1
let DefaultHistoryLength = 10
let MaxHistoryLength = 99

class CommandHistory {
	let historyMenu = NSMenu()
	var commands = [String]()
	var target: NSObject?
	let action: Selector

	init(target:NSObject?, selector:Selector) {
		self.target = target
		self.action = selector
	}
	
	func addToCommandHistory(origQuery:String) {
		var maxLen = NSUserDefaults.standardUserDefaults().integerForKey(PrefMaxCommandHistory)
		if (maxLen < MinHistoryLength) { maxLen = DefaultHistoryLength; }
		if (maxLen > MaxHistoryLength) { maxLen = MaxHistoryLength; }
		let query = origQuery.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		let idx = commands.indexOf(query)
		if idx == nil {
			commands.insert(query, atIndex: 0)
			if commands.count > maxLen { commands.removeLast() }
		} else {
			//already there, need to move to front
			commands.removeAtIndex(idx!)
			commands.insert(query, atIndex: 0)
		}
	}
	
	func adjustCommandHistoryMenu() {
		historyMenu.removeAllItems()
		for aCommand in commands {
			var menuCommand = aCommand
			if aCommand.characters.count > 50 {
				menuCommand = menuCommand.substringToIndex(menuCommand.startIndex.advancedBy(49)).stringByAppendingString("…")
			}
			let menuItem = NSMenuItem(title: menuCommand, action: action, keyEquivalent: "")
			menuItem.target = target
			menuItem.representedObject = aCommand //store full command in case cropped above
			historyMenu.addItem(menuItem)
		}
	}
}
