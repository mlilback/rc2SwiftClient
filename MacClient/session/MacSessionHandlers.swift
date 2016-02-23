//
//  MacSessionHandlers.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc protocol VariableHandler {
	///parameter variables: key is a string, value is an ObjcBox of a JSON value
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,AnyObject>)
}

@objc protocol OutputHandler {
	var imageCache: ImageCache? { get set }
	func appendFormattedString(string:NSAttributedString)
	func saveSessionState() -> AnyObject
	func restoreSessionState(state:[String:AnyObject])
	func prepareForSearch()
	func initialFirstResponder() -> NSResponder
}

@objc protocol FileHandler {
	func filesRefreshed()
	func promptToImportFiles(sender:AnyObject?)
	func validateMenuItem(menuItem: NSMenuItem) -> Bool
}
