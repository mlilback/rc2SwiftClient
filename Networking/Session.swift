//
//  Session.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import Freddy
import MessagePackSwift
import ReactiveSwift
import Result
import SwiftWebSocket
import os
import NotifyingCollection
import ClientCore

public extension Rc2Error {
	public var isSessionError: Bool { return nestedError is SessionError }
}

public enum SessionError: Error, Rc2DomainError {
	case openAlreadyInProgress
}

public enum ExecuteType: String {
	case Run = "run", Source = "source", None = ""
}

public class Session {
	//MARK: properties

	///connection information
	public let conInfo: ConnectionInfo
	//the workspace this session represents
	public let workspace : Workspace
	///the WebSocket for communicating with the server
	// goddamn swift won't let us set a constant that requires invoking a method
	var wsSource : WebSocketSource!
	///abstraction of file handling
	public let fileCache: FileCache
	public let imageCache: ImageCache
	///
	public weak var delegate : SessionDelegate?

	public var project: Project { return conInfo.project(withId: workspace.projectId)! }
	
	///regex used to catch user entered calls to help so we can hijack and display through our mechanism
	var helpRegex : NSRegularExpression = {
		return try! NSRegularExpression(pattern: "(help\\(\\\"?([\\w\\d]+)\\\"?\\))\\s*;?\\s?", options: [.dotMatchesLineSeparators])
	}()
	
	fileprivate var openObserver: Signal<Double, Rc2Error>.Observer?
	public fileprivate(set) var connectionOpen:Bool = false
	fileprivate lazy var keepAliveTimer: DispatchSourceTimer = { DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: UInt(0)), queue: self.queue) }()
	
	///closure syntax for a transaction complete callback
	/// - parameter $0: the transaction id (key in the pendingTransaction dictionary)
	/// - parameter $1: the message received from the server, if available
	fileprivate typealias TransactionCompletion = (String, JSON?) -> Void

	///a dictionary of transaction ids mapped to closures called when the server says the transaction is complete
	fileprivate var pendingTransactions: [String: TransactionCompletion] = [:]
	///if we are getting variable updates from the server
	fileprivate var watchingVariables:Bool = false
	///queue used for async operations
	fileprivate let queue: DispatchQueue
	
	//MARK: init/open/close
	
	/// without a super class, can't use self in designated initializer. So use a private init, and a convenience init for outside use
	private init(connectionInfo: ConnectionInfo, workspace: Workspace, fileCache: FileCache, imageCache: ImageCache, webSocket: WebSocketSource?, queue: DispatchQueue = .main)
	{
		self.workspace = workspace
		self.conInfo = connectionInfo
		self.fileCache = fileCache
		self.imageCache = imageCache
		self.queue = queue
		var ws = webSocket
		if nil == ws {
			ws = WebSocket(request: createWebSocketRequest())
		}
		wsSource = ws
		wsSource.binaryType = .nsData
	}
	
	/// Create a session object
	///
	/// - Parameters:
	///   - connectionInfo: the connection info used for creating REST calls
	///   - workspace: the workspace to use for the session
	///   - delegate: a delegate to handle certain tasks
	///   - fileCache: the file cache to use. Default is to create one
	///   - webSocket: the websocket to use. Defaults to a sensible implementation
	///   - queue: the queue to perform operations on. Defaults to main queue
	public convenience init(connectionInfo: ConnectionInfo, workspace: Workspace, delegate:SessionDelegate?=nil, fileCache: FileCache? = nil, webSocket: WebSocketSource? = nil, queue: DispatchQueue? = nil)
	{
		//create a file cache if one wasn't provided
		var fc = fileCache
		if nil == fc {
			fc = DefaultFileCache(workspace: workspace, baseUrl: connectionInfo.host.url!, config: connectionInfo.urlSessionConfig)
		}
		let rc = Rc2RestClient(connectionInfo, fileManager: fc!.fileManager)
		let ic = ImageCache(restClient: rc, hostIdentifier: connectionInfo.host.name)
		self.init(connectionInfo: connectionInfo, workspace: workspace, fileCache: fc!, imageCache: ic, webSocket: webSocket)
		ic.workspace = workspace
		self.delegate = delegate
		setupWebSocketHandlers()
		
		//setup a timer to send keep alive messages every 2 minutes
		let start = DispatchTime.now() + DispatchTimeInterval.seconds(120)
		keepAliveTimer.scheduleRepeating(deadline: start, interval: .seconds(120), leeway: .milliseconds(100))
		keepAliveTimer.setEventHandler { [unowned self] in
			_ = self.sendMessage(["msg":"keepAlive" as AnyObject])
		}
		keepAliveTimer.resume()
	}
	
	deinit {
		os_log("session dealloc", log: .session, type:.info)
	}
	
	///opens the websocket with the specified request
	/// - parameter request: a ws:// or wss:// request to use for the websocket
	/// - returns: future for the open session (with file loading started) or an error
	public func open(_ request:URLRequest) -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error>() { observer, disposable in
			guard nil == self.openObserver else {
				observer.send(error: Rc2Error(type: .network, nested: SessionError.openAlreadyInProgress))
				return
			}
			self.openObserver = observer
			self.wsSource.open(request: request, subProtocols: [])
		}
	}
	
	///closes the websocket, which can not be reopened
	public func close() {
		keepAliveTimer.cancel()
		self.wsSource.close(1000, reason: "") //default values that can't be specified in a protocol
	}
	
	//MARK: public request methods
	
	///Sends an execute request to the server
	/// - parameter srcScript: the script code to send to the server
	/// - parameter type: whether to run or source the script
	public func executeScript(_ srcScript: String, type:ExecuteType = .Run) {
		//don't send empty scripts
		guard srcScript.characters.count > 0 else {
			return
		}
		var script = srcScript
		let helpCheck = helpRegex.firstMatch(in: script, options: [], range: NSMakeRange(0, script.utf16.count))
		if helpCheck?.numberOfRanges == 3 {
			let topic = script.substring(with: (helpCheck?.rangeAt(2).toStringRange(script))!)
			let adjScript = script.replacingCharacters(in: (helpCheck?.range.toStringRange(script))!, with: "")
			delegate?.respondToHelp(topic)
			guard adjScript.utf16.count > 0 else {
				return
			}
			script = adjScript
		}
		sendMessage(["msg":"execute" as AnyObject, "type":type.rawValue as AnyObject, "code":script as AnyObject])
	}
	
	/// sends a request to execute a script file
	/// - parameter fileId: the id of the file to execute
	/// - parameter type: whether to run or source the file
	public func executeScriptFile(_ fileId:Int, type:ExecuteType = .Run) {
		sendMessage(["msg":"execute" as AnyObject, "type":type.rawValue as AnyObject, "fileId":fileId as AnyObject])
	}
	
	/// clears all variables in the global environment
	public func clearVariables() {
		executeScript("rc2.clearEnvironment()");
	}
	
	/// asks the server for a refresh of all environment variables
	public func forceVariableRefresh() {
		sendMessage(["msg":"watchVariables" as AnyObject, "watch":true as AnyObject])
	}
	
	/// ask the server to send a message with current variable values and delta messages as they change
	public func startWatchingVariables() {
		if (watchingVariables) { return; }
		sendMessage(["msg":"watchVariables" as AnyObject, "watch":true as AnyObject])
		watchingVariables = true
	}

	/// ask the server to stop sending environment delta messages
	public func stopWatchingVariables() {
		if (!watchingVariables) { return }
		sendMessage(["msg":"watchVariables" as AnyObject, "watch":false as AnyObject])
		watchingVariables = false
	}
	
	//TODO: pendingTransactions need to pass errors for all functions using it

	/// Creates an empty file on the server
	///
	/// - Parameters:
	///   - fileName: the name of the file. should be unique
	///   - contentUrl: the contents of the new file if not a copy of an existing file
	///   - originalFileId: if copying a file, the id of the file being copied
	///   - timeout: how long to wait for a file inserted message
	///   - completionHandler: callback with the new file id (after it has been inserted in workspace.files) or an error
	public func create(fileName: String, contentUrl: URL? = nil, timeout: TimeInterval = 2.0, completionHandler: ((Result<Int, Rc2Error>) -> Void)?)
	{
		precondition(workspace.file(withName: fileName) == nil)
		imageCache.restClient.createFile(name: fileName, workspace: workspace, contentUrl: contentUrl)
			.observe(on: UIScheduler()).startWithResult
		{ result in
			guard let file = result.value else {
				completionHandler?(Result<Int, Rc2Error>(error: result.error!))
				return
			}
			//write empty file to cache
			do {
				let updatedFile = try self.workspace.imported(file: file)
				let destUrl = self.fileCache.cachedUrl(file: updatedFile)
				if let srcUrl = contentUrl, srcUrl.fileExists() {
					try self.fileCache.fileManager.copyItem(at: contentUrl!, to: srcUrl)
				} else {
					try Data().write(to: destUrl)
				}
				completionHandler?(Result<Int, Rc2Error>(value: updatedFile.fileId))
			} catch let rc2Err as Rc2Error {
				completionHandler?(Result<Int, Rc2Error>(error: rc2Err))
			} catch {
				completionHandler?(Result<Int, Rc2Error>(error: Rc2Error(type: .cocoa, nested: error)))
			}
		}
	}
	
	/// asks the server to remove a file
	/// - parameter file: The file to remove
	/// - returns: a signal producer that will be complete once the server affirms the file was removed
	@discardableResult
	public func remove(file: File) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error>() { observer, _ in
			let transId = UUID().uuidString
			self.sendMessage(json: .dictionary(["msg": .string("fileop"), "fileId": .int(file.fileId), "fileVersion": .int(file.version), "operation": .string("rm"), "transId": .string(transId)]))
			self.pendingTransactions[transId] = { (responseId, json) in
				observer.sendCompleted()
			}
		}
	}
	
	/// asks the server to rename a file
	/// - parameter file: The file to rename
	/// - parameter to: What to rename it to
	/// - returns: a signal producer that will be complete once the server affirms the file was renamed
	@discardableResult
	public func rename(file: File, to newName: String) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error>() { observer, _ in
			let transId = UUID().uuidString
			self.sendMessage(json: .dictionary(["msg": .string("fileop"), "fileId": .int(file.fileId), "fileVersion": .int(file.version), "operation": .string("rename"), "newName": .string(newName), "transId": .string(transId)]))
			self.pendingTransactions[transId] = { (responseId, json) in
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
	public func duplicate(file: File, to newName: String) -> SignalProducer<Int, Rc2Error> {
		return SignalProducer<Int, Rc2Error>() { observer, _ in
			let transId = UUID().uuidString
			self.sendMessage(json: .dictionary(["msg": .string("fileop"), "fileId": .int(file.fileId), "fileVersion": .int(file.version), "operation": .string("duplicate"), "newName": .string(newName), "transId": .string(transId)]))
			self.pendingTransactions[transId] = { (responseId, json) in
				observer.sendCompleted()
			}
		}
	}
	
	/// send the server a save file message
	///
	/// - Parameters:
	///   - file: the file being saved
	///   - contents: the contents to save
	///   - executeType: should the saved code be executed
	/// - Returns: a signal producer for success or error
	public func sendSaveFileMessage(file: File, contents: String, executeType: ExecuteType = .None)
	{
		os_log("sendSaveFileMessage called on file %d", log: .session, type: .info, file.fileId)
		let uniqueIdent = UUID().uuidString
		let encoder = MessagePackEncoder()
		var attrs = ["msg":MessageValue.forValue("save"), "apiVersion":MessageValue.forValue(Int(1))]
		attrs["transId"] = MessageValue.forValue(uniqueIdent)
		attrs["fileId"] = MessageValue.forValue(file.fileId)
		attrs["fileVersion"] = MessageValue.forValue(file.version)
		attrs["content"] = MessageValue.forValue(contents)
		encoder.encodeValue(MessageValue.DictionaryValue(MessageValueDictionary(attrs)))
		guard let data = encoder.data else {
			os_log("failed to encode save file message", log: .session, type: .error)
			fatalError("failed to encode save file message")
		}
		//for debug purposes
		_ = try? data.write(to: URL(fileURLWithPath: "/tmp/lastSaveToServer"), options: .atomicWrite)
		self.wsSource.send(data)
	}
	
	/// Internally used, and useful for creating a mock websocket
	///
	/// - Returns: a request to open a websocket for this session
	func createWebSocketRequest() -> URLRequest {
		#if os(OSX)
			let client = "osx"
		#else
			let client = "ios"
		#endif
		var components = URLComponents()
		components.host = conInfo.host.host
		components.port = conInfo.host.port
		components.path = "/ws/\(workspace.wspaceId)"
		components.scheme = conInfo.host.secure ? "wss" : "ws"
		components.queryItems = [URLQueryItem(name: "client", value: client),
		                         URLQueryItem(name: "build", value: "\(AppInfo.buildNumber)")]
		var req = URLRequest(url: components.url!)
		//TODO: add header field as constant
		req.addValue(conInfo.authToken, forHTTPHeaderField: "Rc2-Auth")
		req.timeoutInterval = 120
		return req
	}
}

//MARK: private methods
private extension Session {

	///processes a binary response from the WebSocket
	/// - parameter data: The MessagePack data
	func processBinaryResponse(_ data:Data) {
		var parsedValues:[MessageValue]? = nil
		let decoder = MessagePackDecoder(data: data)
		do {
			parsedValues = try decoder.parse()
		} catch let err {
			os_log("error parsing binary message:%{public}@", log: .session, type:.error, err as NSError)
		}
		//get the dictionary of messagevalues
		guard case MessageValue.DictionaryValue(let msgDict) = parsedValues![0] else {
			os_log("received invalid binary response from server", log: .session)
			return
		}
		let dict = msgDict.nativeValue()
		switch dict["msg"] as! String {
		case "saveResponse":
			handleSaveResponse(dict as [String : AnyObject])
		case "showOutput":
			let file = File(dict: dict["file"] as! [String:AnyObject])
			let response = ServerResponse.showOutput(queryId: dict["queryId"] as! Int, updatedFile: file)
			delegate?.sessionMessageReceived(response)
			fileCache.update(file: file, withData: data).start()
		default:
			os_log("received unknown binary message: %{public}@", log: .session, dict["msg"] as! String)
			return
		}
	}
	
	//we've got a dictionary of the save response. keys should be transId, success, file, error
	func handleSaveResponse(_ rawDict:[String:AnyObject]) {
		os_log("handleSaveResponse called", log: .session, type: .info)
		if let transId = rawDict["transId"] as? String {
			os_log("sendSaveFileMessage calling pending transaction", log: .session, type: .info)
			pendingTransactions[transId]?(transId, nil)
			pendingTransactions.removeValue(forKey: transId)
		}
		if let errorDict = rawDict["error"] as? Dictionary<String,AnyObject> {
			//TODO: inform user
			os_log("got save response error: %{public}@", log: .session, type:.error, (errorDict["message"] as? String)!)
			return
		}
		do {
			let fileData = try JSONSerialization.data(withJSONObject: rawDict["file"]!, options: [])
			let json = try JSON(data: fileData)
			let file = try File(json: json)
			try workspace.update(fileId: file.fileId, to: file)
		} catch let updateErr as CollectionNotifierError {
			os_log("update to file failed: %{public}@", log: .session, updateErr.localizedDescription)
		} catch let err as NSError {
			os_log("error parsing binary message: %{public}@", log: .session, type:.error, err)
		}
	}
	
	func handleFileResponse(_ transId:String, operation:FileOperation, file:File) {
		switch(operation) {
		case .Duplicate:
			//no need to do anything, fileUpdated message should arrive
			break
		case .Rename:
			//no need to do anything, fileUpdated message should arrive
			break
		case .Remove:
			do {
				try workspace.remove(file: file)
			} catch {
				os_log("error removing a file", log: .session)
				self.delegate?.sessionErrorReceived(error as! Rc2Error)
			}
			break
		}
	}
	
	func handleReceivedMessage(_ message:Any) {
		if let stringMessage = message as? String {
			guard  let jsonMessage = try? JSON(jsonString: stringMessage),
				let msg = try? jsonMessage.getString(at: "msg") else
			{
				os_log("failed to parse received json: %{public}@", log: .session, type: .info, stringMessage)
				return
			}
			os_log("got message %{public}@", log: .session, msg)
			if let response = ServerResponse.parseResponse(jsonMessage) {
				switch response {
				case .fileOperationResponse(let transId, let operation, let file):
					handleFileResponse(transId, operation:operation, file:file)
				case .fileChanged(let changeType, let file):
					fileCache.flushCache(file: file)
					workspace.update(file: file, change: FileChangeType(rawValue: changeType)!)
				case .execComplete(_, _, let images):
					imageCache.cacheImagesFromServer(images)
					fallthrough
				default:
					queue.async { self.delegate?.sessionMessageReceived(response) }
				}
			}
			if let transId = try? jsonMessage.getString(at: "transId") {
				pendingTransactions[transId]?(transId, jsonMessage)
				pendingTransactions.removeValue(forKey: transId)
			}
		} else if let _ = message as? Data {
			processBinaryResponse(message as! Data)
		} else {
			os_log("invalid binary data format received: %{public}@", log: .session, type:.error)
		}
	}
	
	@discardableResult func sendMessage(json: JSON) -> Bool {
		do {
			self.wsSource.send(try json.serializeString())
		} catch let err as NSError {
			os_log("error sending json message on websocket: %{public}@", log: .session, type:.error, err)
			return false
		}
		return true
	}
	
	@discardableResult func sendMessage(_ message: Dictionary<String, AnyObject>) -> Bool {
		guard JSONSerialization.isValidJSONObject(message) else {
			return false
		}
		do {
			let json = try JSONSerialization.data(withJSONObject: message, options: [])
			let jsonStr = NSString(data: json, encoding: String.Encoding.utf8.rawValue)
			self.wsSource.send(jsonStr as! String)
		} catch let err as NSError {
			os_log("error sending json message on websocket: %{public}@", log: .session, type:.error, err)
			return false
		}
		return true
	}
	
	/// starts file caching and forwards responses to observer from open() call
	private func websocketOpened() {
		fileCache.cacheAllFiles().on(value: { (progPercent) in
			self.openObserver?.send(value: progPercent)
		}, failed: { (cacheError) in
			self.openObserver?.send(error: cacheError)
		}, completed: {
			self.connectionOpen = true
			self.openObserver?.sendCompleted()
			self.openObserver = nil
		}).start()
	}
	
	func setupWebSocketHandlers() {
		wsSource.event.open = { [unowned self] in
			DispatchQueue.global().async {
				self.websocketOpened()
			}
		}
		wsSource.event.close = { [weak self] (code, reason, clear)in
			os_log("websocket closed: %d, %{public}@", log: .session, code, reason)
			self?.connectionOpen = false
			self?.delegate?.sessionClosed()
		}
		wsSource.event.message = { [weak self] message in
			os_log("websocket message: %{public}@", log: .session, type: .debug, message as? String ?? "<binary>")
			self?.queue.async {
				self?.handleReceivedMessage(message)
			}
		}
		wsSource.event.error = { [weak self] error in
			os_log("error from websocket: %{public}@", log: .session, type: .error, error as NSError)
			guard nil == self?.openObserver else {
				self?.openObserver?.send(error: Rc2Error(type: .websocket, nested: error))
				self?.openObserver = nil
				return
			}
			self?.delegate?.sessionErrorReceived(Rc2Error(type: .websocket, nested: error))
		}
	}
}
