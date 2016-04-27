//
//  SessionHandlerProtocols.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///These protocols exist to decouple various view controllers

@objc protocol VariableHandler {
	///parameter variables: key is a string, value is an ObjcBox of a JSON value
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,AnyObject>)
}

@objc enum OutputStringType: Int {
	case Default, Input
}

@objc protocol OutputHandler {
	var imageCache: ImageCache? { get set }
	var session: Session? { get set }
	func appendFormattedString(string:NSAttributedString, type:OutputStringType)
	func saveSessionState() -> AnyObject
	func restoreSessionState(state:[String:AnyObject])
	func prepareForSearch()
	func initialFirstResponder() -> NSResponder
}

@objc protocol FileHandler {
	func filesRefreshed(note:NSNotification?)
	func promptToImportFiles(sender:AnyObject?)
	func validateMenuItem(menuItem: NSMenuItem) -> Bool
}
