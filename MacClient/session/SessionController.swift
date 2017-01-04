//
//  SessionController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import Networking
import Freddy
import ReactiveSwift
import ClientCore
import NotifyingCollection

@objc protocol SessionControllerDelegate {
	func filesRefreshed()
	func sessionClosed()
	func saveState() -> [String: AnyObject]
	func restoreState(_ state:[String: AnyObject])
}

/// manages a Session object
@objc class SessionController: NSObject {
	fileprivate weak var delegate: SessionControllerDelegate?

	var responseHandler: ServerResponseHandler?
	let outputHandler: OutputHandler
	let varHandler: VariableHandler
	let session: Session

	var savedStateHash: Data?
	fileprivate var properlyClosed: Bool = false
	fileprivate var fileLoadDisposable: Disposable?

	init(session: Session, delegate: SessionControllerDelegate, outputHandler output: OutputHandler, variableHandler: VariableHandler)
	{
		self.delegate = delegate
		self.outputHandler = output
		self.varHandler = variableHandler
		self.session = session
		super.init()
		session.delegate = self
		self.responseHandler = ServerResponseHandler(delegate: self)
		let nc = NotificationCenter.default
		nc.addObserver(self, selector: #selector(SessionController.appWillTerminate), name: NSNotification.Name.NSApplicationWillTerminate, object: nil)
		nc.addObserver(self, selector:  #selector(SessionController.saveSessionState), name: NSNotification.Name.NSWorkspaceWillSleep, object:nil)
		restoreSessionState()
	}
	
	deinit {
		if !properlyClosed {
			os_log("not properly closed", log: .app, type:.error)
			close()
		}
	}
	
	func close() {
		fileLoadDisposable?.dispose()
		saveSessionState()
		session.close()
		properlyClosed = true
	}
	
	func appWillTerminate(_ note: Notification) {
		saveSessionState()
	}
	
	func clearFileCache() {
		session.fileCache.flushCache(files: session.workspace.files).start()
	}
	
	func format(errorString: String) -> ResponseString {
		return responseHandler!.formatError(errorString)
	}
}

//MARK: - ServerResponseHandlerDelegate
extension SessionController: ServerResponseHandlerDelegate {
	func handleFileUpdate(_ file: File, change: FileChangeType) {
//		os_log("got file update %d v%d", log: .app, type:.info, file.fileId, file.version)
//		handleFileUpdate(file, change: change)
	}
	
	func handleVariableMessage(_ single: Bool, variables: [Variable]) {
		varHandler.handleVariableMessage(single, variables: variables)
	}
	
	func handleVariableDeltaMessage(_ assigned: [Variable], removed: [String]) {
		varHandler.handleVariableDeltaMessage(assigned, removed: removed)
	}

	func consoleAttachment(forImage image: SessionImage) -> ConsoleAttachment {
		return MacConsoleAttachment(image: image)
	}
	
	func consoleAttachment(forFile file: File) -> ConsoleAttachment {
		return MacConsoleAttachment(file:file)
	}
	
	func attributedStringForInputFile(_ fileId: Int) -> NSAttributedString {
		let file = session.workspace.file(withId: fileId)!
		let str = "[\(file.name)]"
		return NSAttributedString(string: str)
	}
	
	//the file might not be in session yet. if not, wait until it has been added
	func showFile(_ fileId: Int) {
		fileLoadDisposable?.dispose()
		if let existingFile = session.workspace.file(withId: fileId) {
			DispatchQueue.main.async {
				self.outputHandler.showFile(existingFile)
			}
			return
		}
		//TODO: need to wait until file exists then load it
		let handler = { (changes: [CollectionChange<File>]) in
			for aChange in changes {
				if aChange.object?.fileId == fileId {
					//our file was inserted, we can show it
					DispatchQueue.main.async {
						self.outputHandler.showFile(self.session.workspace.file(withId: fileId))
//						self.showFile(fileId)
					}
					break
				}
			}
		}
		fileLoadDisposable = session.workspace.fileChangeSignal.observeValues(handler)
	}
}

//MARK: - save/restore
extension SessionController {
	func stateFileUrl() throws -> URL {
		let fileManager = Foundation.FileManager()
		let appSupportUrl = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		let dataDirUrl = appSupportUrl.appendingPathComponent(AppInfo.bundleIdentifier).appendingPathComponent("sessions", isDirectory: true)
		try fileManager.createDirectory(at: dataDirUrl, withIntermediateDirectories: true, attributes: nil)
		let fname = "\(session.conInfo.host.name)--\(session.project.userId)--\(session.workspace.wspaceId).plist"
		let furl = dataDirUrl.appendingPathComponent(fname)
		return furl
	}
	
	func saveSessionState() {
		//save data related to this session
		var dict = [String:Any]()
		dict["outputController"] = outputHandler.saveSessionState()
		do {
			dict["imageCache"] = try session.imageCache.toJSON().serialize()
		} catch {
		}
		dict["delegate"] = delegate?.saveState()
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
			os_log("Error saving session state: %{public}@", log: .app, err)
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
				if let ic = dict["imageCache"] as? Data, let json = try? JSON(data: ic) {
					try session.imageCache.load(from: json)
				}
				savedStateHash = data.sha256()
			}
		} catch let err as NSError {
			os_log("error restoring session state: %{public}@", log: .app, type:.error, err)
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
	
	func sessionFilesLoaded(_ session: Session) {
		delegate?.filesRefreshed()
	}
	
	func respondToHelp(_ helpTopic: String) {
		outputHandler.showHelp(HelpController.sharedInstance.topicsWithName(helpTopic))
	}
	
	func sessionMessageReceived(_ response: ServerResponse) {
		guard Thread.isMainThread else {
			DispatchQueue.main.async { self.sessionMessageReceived(response) }
			return
		}
		//if not a showoutput message, actually handle the response
		guard case ServerResponse.showOutput( _, let updatedFile) = response else {
			handle(response: response)
			return
		}
		//if the file doesn't exist, wait until it does and then handle the response
		guard let oldFile = session.workspace.file(withId: updatedFile.fileId) else {
			listenForInsert(fileId: updatedFile.fileId) { fileId in
				self.handle(response: response)
			}
			return
		}
		//need to refetch file from server, then show it
		session.fileCache.update(file: oldFile, withData: nil).startWithResult { result in
			guard nil == result.error else {
				os_log("error updating file cache: %{public}s", log: .session, result.error!.errorDescription ?? "??")
				return
			}
			self.handle(response: response)
		}
	}
	
	//TODO: impelment sessionErrorReceived
	func sessionErrorReceived(_ error: Rc2Error) {
		
	}
}

//MARK: - private methods
extension SessionController {
	/// listen for the specified file to be inserted, and then call the handler
	fileprivate func listenForInsert(fileId: Int, handler: @escaping (Int) -> Void) {
		fileLoadDisposable = session.workspace.fileChangeSignal.observeValues { values in
			values.forEach { change in
				if change.changeType == .insert && change.object?.fileId == fileId {
					self.fileLoadDisposable?.dispose()
					handler(fileId)
				}
			}
		}
	}
	
	/// actually handle the response by formatting it and sending it to the output handler
	fileprivate func handle(response: ServerResponse) {
		if let astr = responseHandler?.handleResponse(response) {
			DispatchQueue.main.async {
				self.outputHandler.append(responseString: astr)
			}
		}
	}
}
