//
//  MacSessionEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class SessionEditorController: AbstractSessionViewController {
	@IBOutlet var editor: SessionEditor?
	
	override func viewDidLoad() {
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "fileSelectionChanged:", name: SessionFileSelectionChangedNotification, object: nil)
	}
	
	@IBAction override func performTextFinderAction(sender: AnyObject?) {
		let menuItem = NSMenuItem(title: "foo", action: Selector("performFindPanelAction:"), keyEquivalent: "")
		menuItem.tag = Int(NSFindPanelAction.ShowFindPanel.rawValue)
		editor?.performFindPanelAction(menuItem)
	}
	
	func fileSelectionChanged(note:NSNotification) {
		if let theFile = note.object as! File? {
			theFile.name
		} else {
			//disable editor
			editor?.editable = false
			editor?.textStorage?.deleteCharactersInRange(NSMakeRange(0, (editor?.textStorage!.length)!))
		}
		
	}
}

