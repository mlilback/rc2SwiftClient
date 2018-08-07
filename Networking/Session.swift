//
//  Session.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

#if os(OSX)
	import AppKit
#endif
import Rc2Common
import Foundation
import MJLLogger
import ReactiveSwift
import Result
import Starscream
import Model

public extension Rc2Error {
	public var isSessionError: Bool { return nestedError is SessionError }
}

public enum ExecuteType: String {
	case run = "run", source = "source", none = ""
}

public class Session {
	// MARK: properties

	///connection information
	public let conInfo: ConnectionInfo
	//the workspace this session represents
	public let workspace: AppWorkspace

	///abstraction of file handling
	public let fileCache: FileCache
	public let imageCache: ImageCache
	///
	public weak var delegate: SessionDelegate?
	/// status of compute engine
	public private(set) var computeStatus: SessionResponse.ComputeStatus = .initializing
	
	// swiftlint:disable:next force_try
	public var project: AppProject { return try! conInfo.project(withId: workspace.projectId) }
	
	///regex used to catch user entered calls to help so we can hijack and display through our mechanism
	var helpRegex: NSRegularExpression = {
		// swiftlint:disable:next force_try (hard coded, should never fail)
		return try! NSRegularExpression(pattern: "(help\\(\\\"?([\\w\\d]+)\\\"?\\))\\s*;?\\s?", options: [.dotMatchesLineSeparators])
	}()
	
	private let webSocketWorker: SessionWebSocketWorker
	fileprivate var openObserver: Signal<Double, Rc2Error>.Observer?
	public fileprivate(set) var connectionOpen: Bool = false
	
	///if we are getting variable updates from the server
	fileprivate var watchingVariables: Bool = false
	///queue used for async operations
	fileprivate let queue: DispatchQueue
	private let (sessionLifetime, sessionToken) = Lifetime.make()
	public var lifetime: Lifetime { return sessionLifetime }
	
	private typealias PendingTransactionHandler = (PendingTransaction, SessionResponse, Rc2Error?) -> Void

	private struct PendingTransaction {
		let transId: String
		let command: SessionCommand
		let handler: PendingTransactionHandler
		
		init(transId: String, command: SessionCommand, handler: @escaping PendingTransactionHandler) {
			self.transId = transId
			self.command = command
			self.handler = handler
		}
	}

	///a dictionary of transaction ids mapped to closures called when the server says the transaction is complete
	private var pendingTransactions: [String: PendingTransaction] = [:]

	// MARK: - init/open/close
	
	/// without a super class, can't use self in designated initializer. So use a private init, and a convenience init for outside use
	private init(connectionInfo: ConnectionInfo, workspace: AppWorkspace, fileCache: FileCache, imageCache: ImageCache, wsWorker: SessionWebSocketWorker?, queue: DispatchQueue = .main)
	{
		self.workspace = workspace
		self.conInfo = connectionInfo
		self.fileCache = fileCache
		self.imageCache = imageCache
		self.queue = queue
		var ws = wsWorker
		if nil == ws {
			ws = SessionWebSocketWorker(conInfo: connectionInfo, wspaceId: workspace.wspaceId)
		}
		webSocketWorker = ws!
	}
	
	/// Create a session object
	///
	/// - Parameters:
	///   - connectionInfo: the connection info used for creating REST calls
	///   - workspace: the workspace to use for the session
	///   - delegate: a delegate to handle certain tasks
	///   - fileCache: the file cache to use. Default is to create one
	///   - wsWorker: the websocket to use. Defaults to a sensible implementation
	///   - queue: the queue to perform operations on. Defaults to main queue
	public convenience init(connectionInfo: ConnectionInfo, workspace: AppWorkspace, delegate: SessionDelegate? = nil, fileCache: FileCache? = nil, wsWorker: SessionWebSocketWorker? = nil, queue: DispatchQueue? = nil)
	{
		//create a file cache if one wasn't provided
		var fc = fileCache
		if nil == fc {
			fc = DefaultFileCache(workspace: workspace, baseUrl: connectionInfo.host.url!, config: connectionInfo.urlSessionConfig)
		}
		let rc = Rc2RestClient(connectionInfo, fileManager: fc!.fileManager)
		let ic = ImageCache(restClient: rc, hostIdentifier: connectionInfo.host.name)
		self.init(connectionInfo: connectionInfo, workspace: workspace, fileCache: fc!, imageCache: ic, wsWorker: wsWorker)
		ic.workspace = workspace
		self.delegate = delegate
		webSocketWorker.status.signal.take(during: sessionLifetime).observeValues { [weak self] value in
			self?.webSocketStatusChanged(status: value)
		}
		webSocketWorker.messageSignal.take(during: sessionLifetime).observeValues { [weak self] data in
			self?.handleWebSocket(data: data)
		}
	}
	
	///opens the websocket with the specified request
	/// - returns: future for the open session (with file loading started) or an error
	public func open() -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error> { observer, _ in
			guard nil == self.openObserver else {
				observer.send(error: Rc2Error(type: .network, nested: SessionError.unknown))
				return
			}
			self.openObserver = observer
			self.webSocketWorker.openConnection()
		}.take(during: sessionLifetime)
	}
	
	///closes the websocket, which can not be reopened
	public func close() {
		webSocketWorker.close()
		fileCache.close()
	}
	
	// MARK: - execute
	
	///Sends an execute request to the server
	/// - parameter srcScript: the script code to send to the server
	/// - parameter type: whether to run or source the script
	public func executeScript(_ srcScript: String, type: ExecuteType = .run) {
		//don't send empty scripts
		guard !srcScript.isEmpty else { return }
		var script = srcScript
		let helpCheck = helpRegex.firstMatch(in: script, options: [], range: NSRange(location: 0, length: script.utf16.count))
		if helpCheck?.numberOfRanges == 3 {
			let topic = String(script[(helpCheck?.range(at: 2).toStringRange(script))!])
			let adjScript = script.replacingCharacters(in: (helpCheck?.range.toStringRange(script))!, with: "")
			delegate?.respondToHelp(topic)
			guard !adjScript.utf16.isEmpty else {
				return
			}
			script = adjScript
		}
		// TODO: need to handle execute type, or remove as parameter
		let cmdData = SessionCommand.ExecuteParams(sourceCode: script, transactionId: UUID().uuidString, userInitiated: true, contextId: nil)
		send(command: SessionCommand.execute(cmdData))
	}
	
	/// sends a request to execute a script file
	/// - parameter fileId: the id of the file to execute
	/// - parameter type: whether to run or source the file
	public func execute(file: AppFile, type: ExecuteType = .run) {
		let cmdData = SessionCommand.ExecuteFileParams(file: file.model, transactionId: UUID().uuidString, range: nil, echo: type == .source)
		send(command: SessionCommand.executeFile(cmdData))
	}
	
	// MARK: - environment variables
	/// clears all variables in the global environment
	public func clearVariables() {
		send(command: SessionCommand.clearEnvironment(0))
	}
	
	/// asks the server to delete the named variable
	public func deleteVariable(name: String) {
		// TODO: escape name or create new command that escapes on server
		let cmdData = SessionCommand.ExecuteParams(sourceCode: "rm(\(name))", transactionId: UUID().uuidString, userInitiated: false, contextId: nil)
		send(command: SessionCommand.execute(cmdData))
	}
	
	/// asks the server for a refresh of all environment variables
	public func forceVariableRefresh() {
		// used to have a watch: true argument.
		send(command: SessionCommand.watchVariables(SessionCommand.WatchVariablesParams(watch: true, contextId: nil)))
	}
	
	/// ask the server to send a message with current variable values and delta messages as they change
	public func startWatchingVariables() {
		if watchingVariables { return; }
		send(command: SessionCommand.watchVariables(SessionCommand.WatchVariablesParams(watch: true, contextId: nil)))
		watchingVariables = true
	}

	/// ask the server to stop sending environment delta messages
	public func stopWatchingVariables() {
		if !watchingVariables { return }
		send(command: SessionCommand.watchVariables(SessionCommand.WatchVariablesParams(watch: false, contextId: nil)))
		watchingVariables = false
	}
	
	// MARK: - file handling
	
	/// Creates a new file on the server
	///
	/// - Parameters:
	///   - fileName: the name of the file. should be unique
	///   - contentUrl: the contents of the new file if not a copy of an existing file
	///   - timeout: how long to wait for a file inserted message
	///   - completionHandler: callback with the new file id (after it has been inserted in workspace.files) or an error
	public func create(fileName: String, contentUrl: URL? = nil, timeout: TimeInterval = 2.0, completionHandler: ((Result<Int, Rc2Error>) -> Void)?)
	{
		precondition(workspace.file(withName: fileName) == nil)
		imageCache.restClient.create(fileName: fileName, workspace: workspace, contentUrl: contentUrl)
			.observe(on: UIScheduler()).startWithResult
		{ result in
			guard let file = result.value else {
				completionHandler?(Result<Int, Rc2Error>(error: result.error!))
				return
			}
			//file is on the server, but not necessarily local yet. Pre-cache the data for it
			let sp: SignalProducer<Void, Rc2Error>
			if let srcUrl = contentUrl, srcUrl.fileExists() {
				sp = self.fileCache.cache(file: file, srcFile: srcUrl)
			} else {
				sp = self.fileCache.cache(file: file, withData: Data())
			}
			sp.start { (event) in
				switch event {
					case .failed(let err):
						completionHandler?(Result<Int, Rc2Error>(error: err))
					case .completed:
						self.workspace.whenFileExists(fileId: file.id, within: 2.0).startWithCompleted {
							completionHandler?(Result<Int, Rc2Error>(value: file.id))
						}
					default:
						Log.warn("invalid event from fileCache call", .session)
				}
			}
		}
	}
	
	/// asks the server to remove a file
	/// - parameter file: The file to remove
	/// - returns: a signal producer that will be complete once the server affirms the file was removed
	@discardableResult
	public func remove(file: AppFile) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			let transId = UUID().uuidString
			let reqData = SessionCommand.FileOperationParams(file: file.model, operation: .remove, newName: nil, transactionId: transId)
			let command = SessionCommand.fileOperation(reqData)
			self.send(command: command)
			self.pendingTransactions[transId] = PendingTransaction(transId: transId, command: command)
			{ (_, response, _) in
				guard case let SessionResponse.fileOperation(opData) = response else { return }
				if let err = opData.error {
					observer.send(error: Rc2Error(type: .session, nested: err))
					return
				}
				observer.sendCompleted()
			}
		}
	}
	
	/// asks the server to rename a file
	/// - parameter file: The file to rename
	/// - parameter to: What to rename it to
	/// - returns: a signal producer that will be complete once the server affirms the file was renamed
	@discardableResult
	public func rename(file: AppFile, to newName: String) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			let transId = UUID().uuidString
			let reqData = SessionCommand.FileOperationParams(file: file.model, operation: .rename, newName: newName, transactionId: transId)
			let command = SessionCommand.fileOperation(reqData)
			self.send(command: command)
			self.pendingTransactions[transId] = PendingTransaction(transId: transId, command: command)
			{ (_, response, _) in
				guard case let SessionResponse.fileOperation(opData) = response else { return }
				if let err = opData.error {
					observer.send(error: Rc2Error(type: .session, nested: err))
					return
				}
				observer.sendCompleted()
			}
		}
	}
	
	/// duplicates a file on the server
	///
	/// - Parameters:
	///   - file: the file to duplicate
	///   - newName: the name for the duplicate
	/// - Returns: signal handler with the new file's id or an error
	public func duplicate(file: AppFile, to newName: String) -> SignalProducer<Int, Rc2Error> {
		return SignalProducer<Int, Rc2Error> { observer, _ in
			let transId = UUID().uuidString
			let reqData = SessionCommand.FileOperationParams(file: file.model, operation: .duplicate, newName: newName, transactionId: transId)
			let command = SessionCommand.fileOperation(reqData)
			self.send(command: command)
			self.pendingTransactions[transId] = PendingTransaction(transId: transId, command: command)
			{ (_, response, _) in
				guard case let SessionResponse.fileOperation(opData) = response else { return }
				if let err = opData.error {
					observer.send(error: Rc2Error(type: .session, nested: err))
					return
				}
				// if it was a rename or delete, we're done
				guard let newFile = opData.file else {
					observer.send(value: opData.fileId)
					observer.sendCompleted()
					return
				}
				// for a duplicate, we need to duplcate the file data in the cache for the new file so it doesn't have to be loaded over the network
				self.fileCache.cache(file: newFile, srcFile: self.fileCache.cachedUrl(file: file)).startWithCompleted {
					observer.send(value: opData.fileId)
					observer.sendCompleted()
				}
			}
		}
	}
	
	/// send the server a save file message
	///
	/// - Parameters:
	///   - file: the file being saved
	///   - contents: the contents to save
	///   - executeType: should the saved code be executed
	/// - Returns: a signal producer for success or error. Success always sends a value of true.
	public func sendSaveFileMessage(file: AppFile, contents: String, executeType: ExecuteType = .none) -> SignalProducer<Bool, Rc2Error>
	{
		Log.info("sendSaveFileMessage called on file \(file.fileId)", .session)
		return SignalProducer<Bool, Rc2Error> { observer, _ in
			let transId = UUID().uuidString
			let commandData = SessionCommand.SaveParams(file: file.model, transactionId: transId, content: contents.data(using: .utf8)!)
			let command = SessionCommand.save(commandData)
			self.pendingTransactions[transId] = PendingTransaction(transId: transId, command: command)
			{ (_, response, error) in
				guard case let SessionResponse.save(saveData) = response else { return }
				if let err = error {
					if let sessionError = err.nestedError as? SessionError {
						self.delegate?.sessionErrorReceived(sessionError)
					}
					observer.send(error: err)
					return
				}
				// need to update AppFile to new model
				if let file = saveData.file, let afile = self.workspace.file(withId: file.id) {
					let fchange = SessionResponse.FileChangedData(type: .update, file: file, fileId: afile.fileId)
					try! self.workspace.update(change: fchange) //only throws if unsupported file type, which should not be possible
				}
				observer.send(value: true)
				observer.sendCompleted()
			}
			self.send(command: command)
		}
	}
}

// MARK: FileSaver
extension Session: FileSaver {
	public func save(file: AppFile, contents: String?) -> SignalProducer<Void, Rc2Error> {
		guard let contents = contents else {
			return SignalProducer<Void, Rc2Error>(error: Rc2Error(type: .invalidArgument, explanation: "passed no contents to save"))
		}
		return sendSaveFileMessage(file: file, contents: contents, executeType: .none)
			.map { _ in }
	}
}

// MARK: private methods
private extension Session {
	//we've got a dictionary of the save response. keys should be transId, success, file, error
	func handleSave(response: SessionResponse, data: SessionResponse.SaveData) {
		Log.info("handleSaveResponse called", .session)
		// we want to circumvent the default pending handler, as we need to run it first
		Log.debug("calling pending transaction", .session)
		guard let pending = pendingTransactions[data.transactionId] else {
			fatalError("save message received without pending handler")
		}
		pendingTransactions.removeValue(forKey: data.transactionId)
		// handle error
		if let error = data.error {
			Log.error("got save response error: \(error)", .session)
			pending.handler(pending, response, Rc2Error(type: .session, nested: error))
			return
		}
		// both these could be asserts because they should never happen
		guard let rawFile = data.file else {
			Log.error("got save response w/o file", .session)
			return
		}
		guard let existingFile = workspace.file(withId: rawFile.id) else {
			Log.error("got save response for non-existing file", .session)
			return
		}
		// update file to new version
		existingFile.update(to: rawFile)
		pending.handler(pending, response, nil)
	}
	
	func handleFileOperation(response: SessionResponse.FileOperationData) {
		guard response.error == nil else {
			//error should have been handled via pendingTransaction
			return
		}
		switch response.operation {
		case .duplicate:
			//no need to do anything, fileUpdated message should arrive
			break
		case .rename:
			//no need to do anything, fileUpdated message should arrive
			break
		case .remove:
			//no need to do anything, fileUpdated message should arrive
			break
		}
	}
	
	func handleFileChanged(response: SessionResponse.FileChangedData) {
		do {
			try fileCache.handle(change: response)
			try workspace.update(change: response)
		} catch {
			Log.warn("error handing file change: \(error)", .session)
		}
	}
	
	func handleShowOutput(response: SessionResponse, data: SessionResponse.ShowOutputData) {
		if let ofile = workspace.file(withId: data.file.id) {
			ofile.update(to: data.file) //update file metadata
			guard let fileData = data.fileData else {
				// the file was too large to send via websocket. need to recache and then call delegate
				fileCache.recache(file: ofile).startWithCompleted {
					self.delegate?.sessionMessageReceived(response)
				}
				return
			}
			fileCache.cache(file: ofile.model, withData: fileData).startWithCompleted {
				self.delegate?.sessionMessageReceived(response)
			}
		} else {
			Log.warn("got show output without file downloaded", .session)
			delegate?.sessionMessageReceived(response)
		}
	}
	
	func handleReceivedMessage(_ messageData: Data) {
		let response: SessionResponse
		do {
			if Log.isLogging(.debug, category: .session) {
				let dmsg = "incoming: " + String(data: messageData, encoding: .utf8)!
				Log.debug(dmsg, .session)
			}
			response = try conInfo.decode(data: messageData)
		} catch {
			Log.info("failed to parse received json: \(String(data: messageData, encoding: .utf8) ?? "<invalid>")", .session)
			return
		}
		Log.info("got message \(response)", .session)
		var informDelegate = false
		switch response {
		case .fileOperation(let opData):
			handleFileOperation(response: opData)
		case .fileChanged(let changeData):
			handleFileChanged(response: changeData)
		case .save(let saveData):
			handleSave(response: response, data: saveData)
		case .showOutput(let outputData):
			handleShowOutput(response: response, data: outputData)
		case .info(let infoData):
			conInfo.update(sessionInfo: infoData)
		case .error(let errorData):
			delegate?.sessionErrorReceived(errorData.error)
		case .computeStatus(let status):
			computeStatus = status
			informDelegate = true
		case .execComplete(let execData):
			imageCache.cache(images: execData.images)
			informDelegate = true
		default:
			informDelegate = true
		}
		if informDelegate {
			queue.async { self.delegate?.sessionMessageReceived(response) }
		}
		if let transId = transactionId(for: response), let trans = pendingTransactions[transId] {
			trans.handler(trans, response, nil)
			pendingTransactions.removeValue(forKey: transId)
		}
	}
	
	/// returns the transactionId for the response, if there is one
	// swiftlint:disable cyclomatic_complexity
	private func transactionId(for response: SessionResponse) -> String? {
		switch response {
		case .computeStatus(_):
			return nil
		case .connected:
			return nil
		case .echoExecute(let data):
			return data.transactionId
		case .echoExecuteFile(let data):
			return data.transactionId
		case .error(let err):
			return err.transactionId
		case .execComplete(let data):
			return data.transactionId
		case .fileChanged:
			return nil
		case .fileOperation(let data):
			return data.transactionId
		case .help:
			return nil
		case .results(let data):
			return data.transactionId
		case .save(let data):
			return data.transactionId
		case .showOutput(let data):
			return data.transactionId
		case .variableValue:
			return nil
		case .variables:
			return nil
		case .info:
			return nil
		}
	}
	
	@discardableResult
	func send(command: SessionCommand) -> Bool {
		do {
			let data = try conInfo.encode(command)
			self.webSocketWorker.send(data: data)
		} catch let err as NSError {
			Log.error("error sending message on websocket: \(err)", .session)
			return false
		}
		return true
	}
	
	private func webSocketStatusChanged(status: SessionWebSocketWorker.SocketStatus) {
		switch status {
		case .uninitialized:
			fatalError("status should never change to uninitialized")
		case .connecting:
			Log.debug("connecdtiong", .session)
		case .connected:
			completePostOpenSetup()
		case .closed:
			connectionOpen = false
			delegate?.sessionClosed()
		case .failed(let err):
			// TODO: need to report error to delegate to inform user
			Log.info("websocket error: \(err)")
			connectionOpen = false
			delegate?.sessionClosed()
		}
	}
	
	func handleWebSocket(data: Data) {
		self.queue.async { [weak self] in
			self?.handleReceivedMessage(data)
		}
	}
	
	/// starts file caching and forwards responses to observer from open() call
	private func completePostOpenSetup() {
		fileCache.cacheAllFiles().on(failed: { (cacheError) in
			self.openObserver?.send(error: cacheError)
		}, completed: {
			self.connectionOpen = true
			self.openObserver?.sendCompleted()
			self.openObserver = nil
		}, value: { (progPercent) in
			self.openObserver?.send(value: progPercent)
		}).start()
	}
}
