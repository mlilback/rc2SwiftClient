//
//  CommandHistory.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyUserDefaults

let MinHistoryLength = 1
let DefaultHistoryLength = 10
let MaxHistoryLength = 99

class CommandHistory {
	let historyMenu = NSMenu()
	var commands = [String]()
	var target: NSObject?
	let action: Selector

	init(target: NSObject?, selector: Selector) {
		self.target = target
		self.action = selector
	}
	
	func addToCommandHistory(_ origQuery: String) {
		var maxLen = UserDefaults.standard[.maxCommandHistory]
		if maxLen < MinHistoryLength { maxLen = DefaultHistoryLength }
		if maxLen > MaxHistoryLength { maxLen = MaxHistoryLength }
		let query = origQuery.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
		let idx = commands.index(of: query)
		if idx == nil {
			commands.insert(query, at: 0)
			if commands.count > maxLen { commands.removeLast() }
		} else {
			//already there, need to move to front
			commands.remove(at: idx!)
			commands.insert(query, at: 0)
		}
	}
	
	func adjustCommandHistoryMenu() {
		historyMenu.removeAllItems()
		for aCommand in commands {
			var menuCommand = aCommand
			if aCommand.count > 50 {
				let idx = menuCommand.index(menuCommand.startIndex, offsetBy: 49)
				menuCommand = menuCommand[..<idx] + "…"
			}
			let menuItem = NSMenuItem(title: menuCommand, action: action, keyEquivalent: "")
			menuItem.target = target
			menuItem.representedObject = aCommand //store full command in case cropped above
			historyMenu.addItem(menuItem)
		}
	}
}
