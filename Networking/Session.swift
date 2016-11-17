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
import SwiftWebSocket
import os
import NotifyingCollection

public enum SessionError: Error {
	case openAlreadyInProgress
	case fileCacheError(FileCacheError)
	case websocketError(NSError)
	case internalError
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
	let wsSource : WebSocketSource
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
	
	fileprivate var openObserver: Signal<Double, SessionError>.Observer?
	fileprivate(set) var connectionOpen:Bool = false
	fileprivate var keepAliveTimer:DispatchSource = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: UInt(0)), queue: DispatchQueue.main) /*Migrator FIXME: Use DispatchSourceTimer to avoid the cast*/ as! DispatchSource
	
	///closure syntax for a transaction complete callback
	/// - parameter $0: the transaction id (key in the pendingTransaction dictionary)
	/// - parameter $1: the message received from the server, if available
	fileprivate typealias TransactionCompletion = (String, JSON?) -> Void

	///a dictionary of transaction ids mapped to closures called when the server says the transaction is complete
	fileprivate var pendingTransactions: [String: TransactionCompletion] = [:]
	///if we are getting variable updates from the server
	fileprivate var watchingVariables:Bool = false
	
	
	//MARK: init/open/close
	
	/// without a super class, can't use self in designated initializer. So use a private init, and a convenience init for outside use
	private init(connectionInfo: ConnectionInfo, workspace: Workspace, source:WebSocketSource, fileCache: FileCache, imageCache: ImageCache)
	{
		self.workspace = workspace
		self.wsSource = source
		self.conInfo = connectionInfo
		self.fileCache = fileCache
		self.imageCache = imageCache
	}
	
	convenience init(connectionInfo: ConnectionInfo, workspace: Workspace, source:WebSocketSource = WebSocket(), delegate:SessionDelegate?=nil, config: URLSessionConfiguration = .default, fileCache: FileCache? = nil)
	{
		//create a file cache if one wasn't provided
		var fc = fileCache
		if nil == fc {
			fc = DefaultFileCache(workspace: workspace, baseUrl: connectionInfo.host.url!, config: config)
		}
		let rc = Rc2RestClient(connectionInfo, sessionConfig: config, fileManager: fc!.fileManager)
		let ic = ImageCache(restClient: rc, hostIdentifier: connectionInfo.host.name)
		self.init(connectionInfo: connectionInfo, workspace: workspace, source: source, fileCache: fc!, imageCache: ic)
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
		os_log("session dealloc", type:.info)
	}
	
	///opens the websocket with the specified request
	/// - parameter request: a ws:// or wss:// request to use for the websocket
	/// - returns: future for the open session (with file loading started) or an error
	public func open(_ request:URLRequest) -> SignalProducer<Double, SessionError> {
		return SignalProducer<Double, SessionError>() { observer, disposable in
			guard nil == self.openObserver else {
				observer.send(error: .openAlreadyInProgress)
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
	
	//TODO: pendingTransactions need to pass errors

	/// asks the server to remove a file
	/// - parameter file: The file to remove
	public func remove(file: File) -> SignalProducer<Void, SessionError> {
		return SignalProducer<Void, SessionError>() { observer, _ in
			let transId = UUID().uuidString
			self.sendMessage(["msg":"fileop" as AnyObject, "fileId":file.fileId as AnyObject, "fileVersion":file.version as AnyObject, "operation":"rm" as AnyObject, "transId":transId as AnyObject])
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
	public func sendSaveFileMessage(file: File, contents: String, executeType: ExecuteType = .None) -> SignalProducer<Void, SessionError> {
		let uniqueIdent = UUID().uuidString
		let encoder = MessagePackEncoder()
		var attrs = ["msg":MessageValue.forValue("save"), "apiVersion":MessageValue.forValue(Int(1))]
		attrs["transId"] = MessageValue.forValue(uniqueIdent)
		attrs["fileId"] = MessageValue.forValue(file.fileId)
		attrs["fileVersion"] = MessageValue.forValue(file.version)
		attrs["content"] = MessageValue.forValue(contents)
		encoder.encodeValue(MessageValue.DictionaryValue(MessageValueDictionary(attrs)))
		guard let data = encoder.data else {
			os_log("failed to encode save file message")
			return SignalProducer<Void, SessionError>(error: .internalError)
		}
		//for debug purposes
		_ = try? data.write(to: URL(fileURLWithPath: "/tmp/lastSaveToServer"), options: .atomicWrite)
		return SignalProducer<Void, SessionError>() { observer, _ in
			self.wsSource.send(data)
		}
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
			os_log("error parsing binary message:%{public}s", type:.error, err as NSError)
		}
		//get the dictionary of messagevalues
		guard case MessageValue.DictionaryValue(let msgDict) = parsedValues![0] else {
			os_log("received invalid binary response from server")
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
			os_log("received unknown binary message: %{public}s", dict["msg"] as! String)
			return
		}
	}
	
	//we've got a dictionary of the save response. keys should be transId, success, file, error
	func handleSaveResponse(_ rawDict:[String:AnyObject]) {
		if let transId = rawDict["transId"] as? String {
			pendingTransactions[transId]?(transId, nil)
			pendingTransactions.removeValue(forKey: transId)
		}
		if let errorDict = rawDict["error"] as? Dictionary<String,AnyObject> {
			//TODO: inform user
			os_log("got save response error: %{public}s", type:.error, (errorDict["message"] as? String)!)
			return
		}
		do {
			let fileData = try JSONSerialization.data(withJSONObject: rawDict["file"]!, options: [])
			let json = try JSON(data: fileData)
			let file = try File(json: json)
			try workspace.update(fileId: file.fileId, to: file)
		} catch let updateErr as CollectionNotifierError {
			os_log("update to file failed: %{public}s", updateErr.localizedDescription)
		} catch let err as NSError {
			os_log("error parsing binary message: %{public}s", type:.error, err)
		}
	}
	
	func handleFileResponse(_ transId:String, operation:FileOperation, file:File) {
		switch(operation) {
		case .Duplicate:
			//TODO: support
			break
		case .Rename:
			//TODO: support
			break
		case .Remove:
			do {
				try workspace.remove(file: file)
			} catch {
				os_log("error removing a file")
				self.delegate?.sessionErrorReceived(error)
			}
			break
		}
	}
	
	func handleReceivedMessage(_ message:Any) {
		if let stringMessage = message as? String {
			guard  let jsonMessage = try? JSON(jsonString: stringMessage),
				let msg = try? jsonMessage.getString(at: "msg") else
			{
				os_log("failed to parse received json: %{public}s", stringMessage)
				return
			}
			os_log("got message %{public}s", msg)
			if let response = ServerResponse.parseResponse(jsonMessage) {
				switch response {
				case .fileOperationResponse(let transId, let operation, let file):
					handleFileResponse(transId, operation:operation, file:file)
				case .fileChanged(let changeType, let file):
					workspace.update(file: file, change: FileChangeType(rawValue: changeType)!)
				default:
					self.delegate?.sessionMessageReceived(response)
				}
			}
			if let transId = try? jsonMessage.getString(at: "transId") {
				pendingTransactions[transId]?(transId, jsonMessage)
				pendingTransactions.removeValue(forKey: transId)
			}
		} else if let _ = message as? Data {
			processBinaryResponse(message as! Data)
		} else {
			os_log("invalid binary data format received: %{public}s", type:.error)
		}
	}
	
	@discardableResult func sendMessage(_ message:Dictionary<String,AnyObject>) -> Bool {
		guard JSONSerialization.isValidJSONObject(message) else {
			return false
		}
		do {
			let json = try JSONSerialization.data(withJSONObject: message, options: [])
			let jsonStr = NSString(data: json, encoding: String.Encoding.utf8.rawValue)
			self.wsSource.send(jsonStr as! String)
		} catch let err as NSError {
			os_log("error sending json message on websocket: %{public}s", type:.error, err)
			return false
		}
		return true
	}
	
	/// starts file caching and forwards responses to observer from open() call
	private func websocketOpened() {
		fileCache.cacheAllFiles().on(value: { (progPercent) in
			self.openObserver?.send(value: progPercent)
		}, failed: { (cacheError) in
			self.openObserver?.send(error: .fileCacheError(cacheError))
		}, completed: {
			self.connectionOpen = true
			self.openObserver?.sendCompleted()
			self.openObserver = nil
		}).start()
	}
	
	func setupWebSocketHandlers() {
		wsSource.event.open = { [unowned self] in
			DispatchQueue.main.async {
				self.websocketOpened()
			}
		}
		wsSource.event.close = { [unowned self] (code, reason, clear)in
			self.connectionOpen = false
			self.delegate?.sessionClosed()
		}
		wsSource.event.message = { [unowned self] message in
			self.handleReceivedMessage(message)
		}
		wsSource.event.error = { [unowned self] error in
			guard nil == self.openObserver else {
				self.openObserver?.send(error: .websocketError(error as NSError))
				self.openObserver = nil
				return
			}
			self.delegate?.sessionErrorReceived(error)
		}
	}
}
