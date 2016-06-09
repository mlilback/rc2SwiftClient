//
//  SessionController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc class SessionController: NSObject {
	///only a var because it is required for weak attribute, and we don't want to cause a retain loop with the root controller (which we really shouldn't need to worry about)
	private weak var rootController: RootViewController!
	///var! used because we can't pass self as delegate in constructor until variables initialized
	var responseHandler: ResponseHandler!
	let outputHandler: OutputHandler
	let fileHandler: FileHandler
	let varHandler: VariableHandler
	var imgCache: ImageCache
	///nothing should be called until we have a session
	var session:Session!

	var savedStateHash: NSData?
	private var properlyClosed:Bool = false

	init(rootController root:RootViewController, outputHandler output:OutputHandler, fileHandler: FileHandler, variableHandler:VariableHandler)
	{
		self.rootController = root
		self.outputHandler = output
		self.fileHandler = fileHandler
		self.varHandler = variableHandler
		self.imgCache = ImageCache()
		super.init()
		self.responseHandler = ResponseHandler(delegate: self)
		let nc = NSNotificationCenter.defaultCenter()
		nc.addObserver(self, selector: #selector(SessionController.sessionChanged), name: CurrentSessionChangedNotification, object: nil)
		nc.addObserver(self, selector: #selector(SessionController.appWillTerminate), name: NSApplicationWillTerminateNotification, object: nil)
		nc.addObserver(self, selector:  #selector(SessionController.saveSessionState), name: NSWorkspaceWillSleepNotification, object:nil)
		outputHandler.imageCache = imgCache
	}
	
	deinit {
		if !properlyClosed {
			log.error("not properly closed")
			close()
		}
	}
	
	func close() {
		saveSessionState()
		session.close()
		properlyClosed = true
	}
	
	func sessionChanged(note:NSNotification) {
		session = Session.manager.currentSession
		session.delegate = self
		imgCache.workspace = session.workspace
		outputHandler.session = session
		restoreSessionState()
	}

	func appWillTerminate(note: NSNotification) {
		saveSessionState()
	}
	
}

extension SessionController: ResponseHandlerDelegate {
	func loadHelpItems(topic:String, items:[HelpItem]) {
		//TODO: implement loadHelpItems
	}
	
	func handleFileUpdate(file:File, change:FileChangeType) {
		log.info("got file update \(file.fileId) v\(file.version)")
		session.fileHandler.handleFileUpdate(file, change: change)
	}
	
	func handleVariableMessage(single:Bool, variables:[Variable]) {
		varHandler.handleVariableMessage(single, variables: variables)
	}
	
	func handleVariableDeltaMessage(assigned: [Variable], removed: [String]) {
		varHandler.handleVariableDeltaMessage(assigned, removed: removed)
	}

	func consoleAttachment(forImage image:SessionImage) -> ConsoleAttachment {
		return MacConsoleAttachment(image:image)
	}
	
	func consoleAttachment(forFile file:File) -> ConsoleAttachment {
		return MacConsoleAttachment(file:file)
	}
	
	func attributedStringForInputFile(fileId:Int) -> NSAttributedString {
		let file = session.workspace.fileWithId(fileId)
		return NSAttributedString(string: "[\(file!.name)]")
	}
	
	func cacheImages(images:[SessionImage]) {
		imgCache.cacheImagesFromServer(images)
	}
	
	func showFile(fileId:Int) {
		outputHandler.showFile(fileId)
	}
}

//MARK: - save/restore
extension SessionController {
	func stateFileUrl() throws -> NSURL {
		let fileManager = NSFileManager()
		let appSupportUrl = try fileManager.URLForDirectory(.ApplicationSupportDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
		let dataDirUrl = NSURL(string: "Rc2/sessions/", relativeToURL: appSupportUrl)?.absoluteURL
		try fileManager.createDirectoryAtURL(dataDirUrl!, withIntermediateDirectories: true, attributes: nil)
		let fname = "\(RestServer.sharedInstance.loginSession!.host)--\(session.workspace.userId)--\(session.workspace.wspaceId).plist"
		let furl = NSURL(string:fname, relativeToURL: dataDirUrl)?.absoluteURL
		return furl!
	}
	
	func saveSessionState() {
		//save data related to this session
		var dict = [String:AnyObject]()
		dict["outputController"] = outputHandler.saveSessionState()
		dict["imageCache"] = imgCache
		do {
			let data = NSKeyedArchiver.archivedDataWithRootObject(dict)
			//only write to disk if has changed
			let hash = data.sha256()
			if hash != savedStateHash {
				let furl = try stateFileUrl()
				data.writeToURL(furl, atomically: true)
				savedStateHash = hash
			}
		} catch let err {
			log.error("Error saving session state:\(err)")
		}
	}
	
	private func restoreSessionState() {
		do {
			let furl = try stateFileUrl()
			if furl.checkResourceIsReachableAndReturnError(nil) {
				let data = NSData(contentsOfURL: furl)
				if let dict = NSKeyedUnarchiver.unarchiveObjectWithData(data!) as! [String:AnyObject]? {
					if let ostate = dict["outputController"] as! [String : AnyObject]? {
						outputHandler.restoreSessionState(ostate)
					}
					if let ic = dict["imageCache"] as! ImageCache? {
						imgCache = ic
					}
					savedStateHash = data?.sha256()
				}
			}
		} catch let err {
			log.error("error restoring session state:\(err)")
		}
	}
}

//MARK: SessionDelegate
extension SessionController: SessionDelegate {
	func sessionOpened() {
		
	}
	
	func sessionClosed() {
		rootController.sessionClosedHandler?()
	}
	
	func sessionFilesLoaded(session:Session) {
		fileHandler.filesRefreshed(nil)
	}
	
	func sessionMessageReceived(response:ServerResponse) {
		if case ServerResponse.ShowOutput( _, let updatedFile) = response {
			if updatedFile != session.workspace.fileWithId(updatedFile.fileId) {
				//need to refetch file from server, then show it
				let prog = session.fileHandler.updateFile(updatedFile, withData: nil)
				prog?.rc2_addCompletionHandler() {
					if let astr = self.responseHandler.handleResponse(response) {
						self.outputHandler.appendFormattedString(astr, type: response.isEcho() ? .Input : .Default)
					}
					//					self.outputHandler?.appendFormattedString(self.consoleAttachment(forFile:updatedFile).serializeToAttributedString(), type:.Default)
				}
				return
			}
		}
		if let astr = responseHandler.handleResponse(response) {
			outputHandler.appendFormattedString(astr, type: response.isEcho() ? .Input : .Default)
		}
	}
	
	//TODO: impelment sessionErrorReceived
	func sessionErrorReceived(error:ErrorType) {
		
	}
}

