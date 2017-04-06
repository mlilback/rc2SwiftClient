//
//  SessionController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import Networking
import Freddy
import SwiftyUserDefaults
import ReactiveSwift
import ReactiveCocoa
import Result
import ClientCore
import NotifyingCollection

protocol SessionControllerDelegate: class {
	func filesRefreshed()
	func sessionClosed()
	func saveState() -> JSON
	func restoreState(_ state: JSON)
}

/// manages a Session object
@objc class SessionController: NSObject, ServerResponseHandlerDelegate {
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
	
	func clearImageCache() {
		session.imageCache.clearCache()
	}
	
	func format(errorString: String) -> ResponseString {
		return responseHandler!.formatError(errorString)
	}

	// MARK: - ServerResponseHandlerDelegate
	
	func handleFileUpdate(fileId: Int, file: File?, change: FileChangeType) {
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

// MARK: - save/restore
extension SessionController {
	func stateFileUrl() throws -> URL {
		let dataDirUrl = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "sessions")
		let fname = "\(session.conInfo.host.name)--\(session.project.userId)--\(session.workspace.wspaceId).json"
		let furl = dataDirUrl.appendingPathComponent(fname)
		return furl
	}
	
	func saveSessionState() {
		//save data related to this session
		var dict = [String: JSON]()
		dict["outputController"] = outputHandler.saveSessionState()
		dict["imageCache"] = session.imageCache.toJSON()
		dict["delegate"] = delegate?.saveState()
		do {
			let data = try JSON.dictionary(dict).serialize()
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
				guard let json = try? JSON(data: data), let jsonDict = try? json.getDictionary() else { return }
				if let outputState = jsonDict["outputController"] {
					outputHandler.restoreSessionState(outputState)
				}
				if let editState = jsonDict["delegate"] {
					delegate?.restoreState(editState)
				}
				if let imageState = jsonDict["imageCache"] {
					try session.imageCache.load(from: imageState)
				}
				savedStateHash = data.sha256()
			}
		} catch let err as NSError {
			os_log("error restoring session state: %{public}@", log: .app, type:.error, err)
		}
	}
}

// MARK: - SessionDelegate
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
		outputHandler.showHelp(HelpController.shared.topicsWithName(helpTopic))
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

// MARK: - private methods
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
