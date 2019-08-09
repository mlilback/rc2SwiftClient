//
//  SessionController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import Networking
import ClientCore
import SwiftyUserDefaults
import ReactiveSwift
import ReactiveCocoa
import Result
import Rc2Common
import Model

protocol SessionControllerDelegate: class {
	func filesRefreshed()
	func sessionClosed()
	func save(state: inout SessionState)
	func restore(state: SessionState)
}

// MARK: -
/// The SessionController is the owner/delgate of the session. It aggregates functionality/properties needed throughout the view heirarchy
@objc class SessionController: NSObject {
	// MARK: properties
	fileprivate weak var delegate: SessionControllerDelegate?

	var responseFormatter: SessionResponseFormatter!
	let codeEditor: EditorManager
	let outputHandler: OutputHandler
	let varHandler: VariableHandler
	let session: Session
	var appStatus: MacAppStatus?

	var savedStateHash: Data?
	fileprivate var properlyClosed: Bool = false
	fileprivate var fileLoadDisposable: Disposable?
	private var computeStatus: SessionResponse.ComputeStatus?
	private var computeStatusObserver: Signal<Bool, Rc2Error>.Observer?
	
	// MARK: methods
	
	init(session: Session, delegate: SessionControllerDelegate, editor: EditorManager, outputHandler output: OutputHandler, variableHandler: VariableHandler)
	{
		self.delegate = delegate
		self.codeEditor = editor
		self.outputHandler = output
		self.varHandler = variableHandler
		self.session = session
		super.init()
		session.delegate = self
		self.responseFormatter = DefaultResponseFormatter(delegate: self)
//		self.responseHandler = ServerResponseHandler(delegate: self)
		let nc = NotificationCenter.default
		nc.addObserver(self, selector: #selector(SessionController.appWillTerminate), name: NSApplication.willTerminateNotification, object: nil)
		nc.addObserver(self, selector:  #selector(SessionController.saveSessionState), name: NSWorkspace.willSleepNotification, object:nil)
		// need to finish the init process we are a part of
		DispatchQueue.main.async {
			self.restoreSessionState()
		}
	}

	deinit {
		if !properlyClosed {
			Log.error("not properly closed", .app)
			close()
		}
	}
	
	func close() {
		fileLoadDisposable?.dispose()
		fileLoadDisposable = nil
		saveSessionState()
		session.close()
		properlyClosed = true
	}
	
	@objc func appWillTerminate(_ note: Notification) {
		saveSessionState()
	}
	
	func clearFileCache() {
		session.fileCache.flushCache(files: session.workspace.files).start()
	}
	
	func clearImageCache() {
		session.imageCache.clearCache()
	}
	
	func format(errorString: String) -> ResponseString? {
		return responseFormatter.formatError(string: errorString)
	}

	// MARK: - ServerResponseHandlerDelegate
	
	func handleFileUpdate(fileId: Int, file: AppFile?, change: FileChangeType) {
//		os_log("got file update %d v%d", log: .app, type:.info, file.fileId, file.version)
//		handleFileUpdate(file, change: change)
	}
	
//	func handleVariableMessage(_ single: Bool, variables: [Variable]) {
//		varHandler.handleVariableMessage(single, variables: variables)
//	}
//	
//	func handleVariableDeltaMessage(_ assigned: [Variable], removed: [String]) {
//		varHandler.handleVariableDeltaMessage(assigned, removed: removed)
//	}

	//the file might not be in session yet. if not, wait until it has been added
	func showFile(_ fileId: Int) {
		fileLoadDisposable?.dispose()
		if let existingFile = session.workspace.file(withId: fileId) {
			DispatchQueue.main.async {
				self.outputHandler.show(file: existingFile)
			}
			return
		}
		// wait for file to be updated if necessary
		let handler = { (changes: [AppWorkspace.FileChange]) in
			for aChange in changes where aChange.file.fileId == fileId {
				//our file was inserted, we can show it
				DispatchQueue.main.async {
					self.outputHandler.show(file: self.session.workspace.file(withId: fileId))
//						self.showFile(fileId)
				}
				break
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
	
	@objc func saveSessionState() {
		var state = SessionState()
		outputHandler.save(state: &state.outputState)
		delegate?.save(state: &state)
		do {
			try session.imageCache.save(state: &state.imageCacheState)
			let data = try state.serialize()
			let hash = (data as NSData).sha256()
			if hash != savedStateHash, let furl = try? stateFileUrl() {
				try? data.write(to: furl)
				savedStateHash = hash
			}
		} catch {
			Log.error("failed to save sesison state: \(error)", .session)
		}
	}
	
	private func restoreSessionState() {
		do {
			let furl = try stateFileUrl()
			if FileManager.default.fileExists(atPath: furl.path),
				let data = try? Data(contentsOf: furl),
				data.count > 0
			{
				let state = try SessionState(from: data)
				outputHandler.restore(state: state.outputState)
				delegate?.restore(state: state)
				try session.imageCache.restore(state: state.imageCacheState)
				savedStateHash = (data as NSData).sha256()
			}
		} catch {
			Log.error("error restoring session state: \(error)", .session)
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
	
	func sessionMessageReceived(_ response: SessionResponse) {
		guard Thread.isMainThread else {
			DispatchQueue.main.async { self.sessionMessageReceived(response) }
			return
		}
		handle(response: response)
	}
	
	func sessionErrorReceived(_ error: SessionError) {
		let defaults = UserDefaults.standard
		switch error {
		case .compute(_, let details, _):
			let errorDetails = details ?? "unknown error"
			let theme = ThemeManager.shared.activeOutputTheme.value
			var attrs = theme.stringAttributes(for: .error)
			attrs[NSAttributedString.Key.font] = NSFont.userFixedPitchFont(ofSize: CGFloat(defaults[DefaultsKeys.defaultFontSize]))
			let fstr = NSAttributedString(string: errorDetails, attributes: attrs)
			let rstring = ResponseString(string: fstr, type: .error)
			output(responseString: rstring)
			break
		default:
			output(responseString: responseFormatter.formatError(string: error.localizedDescription))
		}
	}
}

// MARK: - private methods
extension SessionController {
	/// listen for the specified file to be inserted, and then call the handler
	fileprivate func listenForInsert(fileId: Int, handler: @escaping (Int) -> Void) {
		fileLoadDisposable = session.workspace.fileChangeSignal.observeValues { values in
			values.forEach { change in
				if change.type == .add && change.file.fileId == fileId {
					self.fileLoadDisposable?.dispose()
					handler(fileId)
				}
			}
		}
	}
	
	private func updateCompute(status: SessionResponse.ComputeStatus) {
		if nil == computeStatus {
			Log.debug("session.updadateCompute with nil status", .session)
			// start progress for compute setup
			SignalProducer<Bool, Rc2Error> { observer, _ in
				self.computeStatusObserver = observer
			}
			.updateProgress(status: appStatus!, actionName: "Launching R", converter: { _ in
				return ProgressUpdate(.start, message: "Launching R")
			})
			.start(on: UIScheduler()).startWithCompleted {
				self.computeStatusObserver?.sendCompleted()
			}
		}
		computeStatus = status
		if case SessionResponse.ComputeStatus.running = status {
			/// end compute progress
			computeStatusObserver?.sendCompleted()
		}
	}
	
	/// actually handle the response by formatting it and sending it to the output handler
	fileprivate func handle(response: SessionResponse) {
		switch response {
		case .variableValue(let varData):
			varHandler.variableUpdated(varData)
			return
		case .variables(let varData):
			varHandler.variablesUpdated(varData)
			return
		case .showOutput(let outputData):
			guard UserDefaults.standard[.openGeneratedFiles] else { break }
			showFile(outputData.file.id)
		case .computeStatus(let status):
			updateCompute(status: status)
		default:
			break
		}
		if let astr = responseFormatter.format(response: response) {
			output(responseString: astr)
		}
	}
	
	private func output(responseString: ResponseString) {
		DispatchQueue.main.async {
			self.outputHandler.append(responseString: responseString)
		}
	}
}

extension SessionController: SessionResponseFormatterDelegate {
	func consoleAttachment(forImage image: SessionImage) -> ConsoleAttachment {
		return MacConsoleAttachment(image: image)
	}
	
	func consoleAttachment(forFile file: File) -> ConsoleAttachment {
		return MacConsoleAttachment(file: file)
	}
	
	func attributedStringForInputFile(_ fileId: Int) -> NSAttributedString {
		let file = session.workspace.file(withId: fileId)!
		let str = "[\(file.name)]"
		return NSAttributedString(string: str)
	}
}
