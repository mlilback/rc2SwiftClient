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
	func handleVariableMessage(_ single:Bool, variables:[Variable])
	
	/// handle a delta change message
	/// - parameter assigned: variabless that were assigned (insert or update)
	/// - parameter: removed: variables that werer deleted
	func handleVariableDeltaMessage(_ assigned:[Variable], removed:[String])
}

@objc enum OutputStringType: Int {
	case `default`, input
}

@objc protocol OutputHandler {
	var sessionController: SessionController? { get set }
	func appendFormattedString(_ string:NSAttributedString, type:OutputStringType)
	func saveSessionState() -> AnyObject
	func restoreSessionState(_ state:[String:AnyObject])
	func prepareForSearch()
	func initialFirstResponder() -> NSResponder
	//use fileId instead of file object because File is a swift struct and can't be used in an objc protocol
	//also get weird compile errors if fileId is made Int?. so passing a zero is the same as nil
	func showFile(_ fileId:Int)
	func showHelp(_ topics:[HelpTopic])
}

@objc protocol FileHandler {
	func filesRefreshed(_ note:Notification?)
	func promptToImportFiles(_ sender:AnyObject?)
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
}
