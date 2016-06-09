//
//  SessionHandlerProtocols.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///These protocols exist to decouple various view controllers

/// Abstracts the idea of processing variable messages
@objc protocol VariableHandler {
	///parameter variables: key is a string, value is an ObjcBox of a JSON value
	/// - parameter single: if this is an update for a single variable, or a delta
	/// - paramter variables: the variable objects from the server
	func handleVariableMessage(single:Bool, variables:[Variable])
	
	/// handle a delta change message
	/// - parameter assigned: variabless that were assigned (insert or update)
	/// - parameter: removed: variables that werer deleted
	func handleVariableDeltaMessage(assigned:[Variable], removed:[String])
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
	//use fileId instead of file object because File is a swift struct and can't be used in an objc protocol
	//also get weird compile errors if fileId is made Int?. so passing a zero is the same as nil
	func showFile(fileId:Int)
	func showHelp(topics:[HelpTopic])
}

@objc protocol FileHandler {
	func filesRefreshed(note:NSNotification?)
	func promptToImportFiles(sender:AnyObject?)
	func validateMenuItem(menuItem: NSMenuItem) -> Bool
}
