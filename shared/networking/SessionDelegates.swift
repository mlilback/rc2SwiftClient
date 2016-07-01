//
//  SessionDelegates.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

protocol SessionDelegate : class {
	///called when the session is closed. Called when explicity or remotely closed. Not called on application termination
	func sessionClosed()
	///called when a server response is received and not handled internally by the session
	func sessionMessageReceived(response:ServerResponse)
	///called when the server has returned an error. Delegate needs to associate it with the cause and error.
	func sessionErrorReceived(error:ErrorType)
	///called when the initial caching/loading of files is complete
	func sessionFilesLoaded(session:Session)
	///a script/file had a call to help with the passed in arguments
	func respondToHelp(helpTopic:String)
}

protocol SessionFileHandlerDelegate: class {
	func filesLoaded()
}

///Abstracts handling of files by the session to allow changes or DI
protocol SessionFileHandler : class {
	var workspace:Workspace { get set }
	var fileCache:FileCache { get }
	var fileDelegate:SessionFileHandlerDelegate? { get set }
	
	func loadFiles()
	///handle file change that requires refetching contents
	func handleFileUpdate(file:File, change:FileChangeType)
	//handle file change that might contain the file's contents
	func updateFile(file:File, withData data:NSData?) -> NSProgress?
	func contentsOfFile(file:File) -> Future<NSData?,FileError>
	//the following will add the save operation to a serial queue to be executed immediately
	func saveFile(file:File, contents:String, completionHandler:(NSError?) -> Void)
}
