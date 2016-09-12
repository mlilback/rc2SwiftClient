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
	func sessionMessageReceived(_ response:ServerResponse)
	///called when the server has returned an error. Delegate needs to associate it with the cause and error.
	func sessionErrorReceived(_ error:Error)
	///called when the initial caching/loading of files is complete
	func sessionFilesLoaded(_ session:Session)
	///a script/file had a call to help with the passed in arguments
	func respondToHelp(_ helpTopic:String)
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
	func handleFileUpdate(_ file:File, change:FileChangeType)
	//handle file change that might contain the file's contents
	@discardableResult func updateFile(_ file:File, withData data:Data?) -> Progress?
	func contentsOfFile(_ file:File) -> Future<Data?,FileError>
	//the following will add the save operation to a serial queue to be executed immediately
	func saveFile(_ file:File, contents:String, completionHandler: @escaping (NSError?) -> Void)
}
