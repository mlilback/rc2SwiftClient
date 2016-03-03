//
//  SessionDelegates.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

protocol SessionDelegate : class {
	func sessionOpened()
	func sessionClosed()
	func sessionMessageReceived(response:ServerResponse)
	func sessionErrorReceived(error:ErrorType)
	func loadHelpItems(topic:String, items:[HelpItem])
	func sessionFilesLoaded(session:Session)
}

protocol SessionFileHandlerDelegate: class {
	func filesLoaded()
}

protocol SessionFileHandler : class {
	var workspace:Workspace { get set }
	var fileCache:FileCache { get }
	var fileDelegate:SessionFileHandlerDelegate? { get set }
	
	func loadFiles()
	func contentsOfFile(file:File) -> Future<NSData?,FileError>
	//the following will add the save operation to a serial queue to be executed immediately
	func saveFile(file:File, contents:String, completionHandler:(NSError?) -> Void)
}
