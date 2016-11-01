//
//  SessionController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os

@objc protocol SessionControllerDelegate {
	func filesRefreshed()
	func sessionClosed()
	func saveState() -> [String:AnyObject]
	func restoreState(_ state:[String:AnyObject])
}

/// manages a Session object
@objc class SessionController: NSObject {
	fileprivate weak var delegate: SessionControllerDelegate?

	///var! used because we can't pass self as delegate in constructor until variables initialized
	var responseHandler: ServerResponseHandler!
	let outputHandler: OutputHandler
	let varHandler: VariableHandler
	///not a constant because it can be saved/loaded
	var imageCache: ImageCache!

	let session:Session

	var savedStateHash: Data?
	fileprivate var properlyClosed:Bool = false

	init(session:Session, delegate: SessionControllerDelegate, outputHandler output:OutputHandler, variableHandler:VariableHandler)
	{
		self.delegate = delegate
		self.outputHandler = output
		self.varHandler = variableHandler
		self.session = session
		super.init()
		session.delegate = self
		imageCache = ImageCache(restServer: session.restServer!, fileManager:Foundation.FileManager(), hostIdentifier: UUID().uuidString)
		imageCache.workspace = session.workspace
		self.responseHandler = ServerResponseHandler(delegate: self)
		let nc = NotificationCenter.default
		nc.addObserver(self, selector: #selector(SessionController.appWillTerminate), name: NSNotification.Name.NSApplicationWillTerminate, object: nil)
		nc.addObserver(self, selector:  #selector(SessionController.saveSessionState), name: NSNotification.Name.NSWorkspaceWillSleep, object:nil)
		restoreSessionState()
	}
	
	deinit {
		if !properlyClosed {
			os_log("not properly closed", type:.error)
			close()
		}
	}
	
	func close() {
		saveSessionState()
		session.close()
		properlyClosed = true
	}
	
	func appWillTerminate(_ note: Notification) {
		saveSessionState()
	}
	
	func clearFileCache() {
		session.fileHandler.fileCache.flushCache(workspace:session.workspace)
	}
	
	func formatErrorMessage(_ error:String) -> NSAttributedString {
		return responseHandler!.formatError(error)
	}
}

//MARK: - ServerResponseHandlerDelegate
extension SessionController: ServerResponseHandlerDelegate {
	func handleFileUpdate(_ file:File, change:FileChangeType) {
		os_log("got file update %d v%d", type:.info, file.fileId, file.version)
		session.fileHandler.handleFileUpdate(file, change: change)
	}
	
	func handleVariableMessage(_ single:Bool, variables:[Variable]) {
		varHandler.handleVariableMessage(single, variables: variables)
	}
	
	func handleVariableDeltaMessage(_ assigned: [Variable], removed: [String]) {
		varHandler.handleVariableDeltaMessage(assigned, removed: removed)
	}

	func consoleAttachment(forImage image:SessionImage) -> ConsoleAttachment {
		return MacConsoleAttachment(image:image)
	}
	
	func consoleAttachment(forFile file:File) -> ConsoleAttachment {
		return MacConsoleAttachment(file:file)
	}
	
	func attributedStringForInputFile(_ fileId:Int) -> NSAttributedString {
		let file = session.workspace.fileWithId(fileId)
		return NSAttributedString(string: "[\(file!.name)]")
	}
	
	func cacheImages(_ images:[SessionImage]) {
		imageCache.cacheImagesFromServer(images)
	}
	
	func showFile(_ fileId:Int) {
		outputHandler.showFile(fileId)
	}
}

//MARK: - save/restore
extension SessionController {
	func stateFileUrl() throws -> URL {
		let fileManager = Foundation.FileManager()
		let appSupportUrl = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		let dataDirUrl = URL(string: "Rc2/sessions/", relativeTo: appSupportUrl)?.absoluteURL
		try fileManager.createDirectory(at: dataDirUrl!, withIntermediateDirectories: true, attributes: nil)
		let fname = "\(session.restServer!.host.name)--\(session.workspace.project!.userId)--\(session.workspace.wspaceId).plist"
		let furl = dataDirUrl?.appendingPathComponent(fname)
		return furl!
	}
	
	func saveSessionState() {
		//save data related to this session
		var dict = [String:AnyObject]()
		dict["outputController"] = outputHandler.saveSessionState()
		dict["imageCache"] = imageCache
		dict["delegate"] = delegate?.saveState() as AnyObject?
		do {
			let data = NSKeyedArchiver.archivedData(withRootObject: dict)
			//only write to disk if has changed
			let hash = data.sha256()
			if hash != savedStateHash {
				let furl = try stateFileUrl()
				try? data.write(to: furl, options: [.atomic])
				savedStateHash = hash
			}
		} catch let err as NSError {
			os_log("Error saving session state: %{public}s", err)
		}
	}
	
	fileprivate func restoreSessionState() {
		do {
			let furl = try stateFileUrl()
			if (furl as NSURL).checkResourceIsReachableAndReturnError(nil),
				let data = try? Data(contentsOf: furl)
			{
				guard let dict = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data as NSData) as? [String:AnyObject] else {
					return
				}
				if let ostate = dict["outputController"] as? [String : AnyObject] {
					outputHandler.restoreSessionState(ostate)
				}
				if let edict = dict["delegate"] as? [String : AnyObject] {
					delegate?.restoreState(edict)
				}
				if let ic = dict["imageCache"] as! ImageCache? {
					ic.workspace = self.session.workspace
					imageCache = ic
				}
				savedStateHash = data.sha256()
			}
		} catch let err as NSError {
			os_log("error restoring session state: %{public}s", type:.error, err)
		}
	}
}

//MARK: - SessionDelegate
extension SessionController: SessionDelegate {
	func sessionOpened() {
		
	}
	
	func sessionClosed() {
		delegate?.sessionClosed()
	}
	
	func sessionFilesLoaded(_ session:Session) {
		delegate?.filesRefreshed()
	}
	
	func respondToHelp(_ helpTopic: String) {
		outputHandler.showHelp(HelpController.sharedInstance.topicsWithName(helpTopic))
	}
	
	func sessionMessageReceived(_ response:ServerResponse) {
		if case ServerResponse.showOutput( _, let updatedFile) = response {
			if updatedFile != session.workspace.fileWithId(updatedFile.fileId) {
				//need to refetch file from server, then show it
				let prog = session.fileHandler.updateFile(updatedFile, withData: nil)
				prog?.rc2_addCompletionHandler() {
					if let astr = self.responseHandler.handleResponse(response) {
						self.outputHandler.appendFormattedString(astr, type: response.isEcho() ? .input : .default)
					}
					//					self.outputHandler?.appendFormattedString(self.consoleAttachment(forFile:updatedFile).serializeToAttributedString(), type:.Default)
				}
				return
			}
		}
		if let astr = responseHandler.handleResponse(response) {
			outputHandler.appendFormattedString(astr, type: response.isEcho() ? .input : .default)
		}
	}
	
	//TODO: impelment sessionErrorReceived
	func sessionErrorReceived(_ error:Error) {
		
	}
}

