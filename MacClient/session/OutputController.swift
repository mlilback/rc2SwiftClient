//
//  OutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class OutputController: NSTabViewController, SessionOutputHandler {
	var consoleController: SessionConsoleController?
	var imageCache: ImageCache?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		selectedTabViewItemIndex = 0
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = displayFileOrImage
	}
	
	func displayFileOrImage(fileWrapper: NSFileWrapper) {
		log.info("told to display file \(fileWrapper.filename)")
	}

	func appendFormattedString(string:NSAttributedString) {
		consoleController?.appendFormattedString(string)
	}
	
	func saveSessionState() -> AnyObject {
		var dict = [String:AnyObject]()
		dict["console"] = consoleController?.saveSessionState()
		return dict
	}
	
	func restoreSessionState(state:[String:AnyObject]) {
		if let consoleState = state["console"] as? [String:AnyObject] {
			consoleController?.restoreSessionState(consoleState)
		}
	}
}

