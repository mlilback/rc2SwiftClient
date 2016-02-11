//
//  SessionDelegates.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation


protocol SessionDelegate : class {
	func sessionOpened()
	func sessionClosed()
	func sessionMessageReceived(response:ServerResponse)
	func sessionErrorReceived(error:ErrorType)
	func loadHelpItems(topic:String, items:[HelpItem])
}

@objc protocol SessionVariableHandler {
	///parameter variables: key is a string, value is an ObjcBox of a JSON value
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,AnyObject>)
}

@objc protocol SessionOutputHandler {
	var imageCache: ImageCache? { get set }
	func appendFormattedString(string:NSAttributedString)
	func saveSessionState() -> AnyObject
	func restoreSessionState(state:[String:AnyObject])
	func prepareForSearch()
}


