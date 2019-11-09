//
//  MacAppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking
import ReactiveSwift
import Rc2Common
import MJLLogger

///used to update the progress display for an operation
struct ProgressUpdate {
	///possible stages of progress update
	enum Stage {
		case start, value, completed, failed
	}
	/// the stage of progress represented by this update
	let stage: Stage
	/// for a .value stage, a description to display to the user
	let message: String?
	/// for a .value stage, the percent complete (0...1) or -1 if indeterminate/not applicable
	let value: Double
	/// for a .failed stage, the error that caused the failure
	let error: Rc2Error?
	/// for a .start stage, determines if user interaction should be disabled
	let disableInput: Bool
	
	init(_ stage: Stage, message: String? = nil, value: Double = -1, error: Rc2Error? = nil, disableInput: Bool = true) {
		self.stage = stage
		self.message = message
		self.value = value
		self.error = error
		self.disableInput = disableInput
	}
}

/// represents the status of a session/window pair
class MacAppStatus {
	/// a signal to observe to receive progress updates
	let progressSignal: Signal<ProgressUpdate, Never>
	/// a signal to know if the status is busy
	let busySignal: Signal<Bool, Never>
	/// callback to get the window for a particular session
	public let getWindow: (Session?) -> NSWindow?
	/// queue used for changes to the current operation
	private let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)
	/// tracks if an operation is in progress, and to eventually support canceling
//	private var currentDisposable: Disposable? {
//		get {
//			var disp: Disposable?
//			_statusQueue.sync { disp = _currentDisposable }
//			return disp
//		}
//		set { _statusQueue.sync { _currentDisposable = newValue } }
//	}
	/// underlying value that should always be interacted with via currentDisposable which is thread-safe
	private var _currentDisposable: Disposable?
	/// tne name of the current action to display in completed/canceled status messages
	private var currentActionName: String?
	/// observer for sending progress updates
	private let progressObserver: Signal<ProgressUpdate, Never>.Observer
	/// observer for sending busy events
	private let busyObserver: Signal<Bool, Never>.Observer
	
	@objc dynamic var busy: Bool {
		var result = false
		_statusQueue.sync { result = _currentDisposable != nil }
		return result
	}
	
	init(windowAccessor: @escaping (Session?) -> NSWindow?) {
		getWindow = windowAccessor
		(progressSignal, progressObserver) = Signal<ProgressUpdate, Never>.pipe()
		(busySignal, busyObserver) = Signal<Bool, Never>.pipe()
	}
	
	/// called when a signal producer to display progress is started
	///
	/// - Parameters:
	///   - name: the name of the action being started
	///   - disposable: the disposable for the action that is starting
	fileprivate func actionStarting(name: String, disposable: Disposable, determinate: Bool) {
		Log.info("starting action \(name)", .app)
		// FIXME: if debugging, this can happen after action is finished and the assert will fail
		_statusQueue.sync {
			assert(nil == _currentDisposable)
			currentActionName = name
			_currentDisposable = disposable
			progressObserver.send(value: ProgressUpdate(.start, message: currentActionName, value: determinate ? 0 : -1))
			busyObserver.send(value: true)
		}
	}
	
	/// Handles an progress update for the current action
	///
	/// - Parameter event: the progress update event passed on via the progressSignal
	fileprivate func process(_ event: Signal<ProgressUpdate, Rc2Error>.Event) {
		var ended: Bool = true
		switch event {
		case .value(let value):
			assert(value.stage == .value)
			progressObserver.send(value: value)
			ended = false
		case .failed(let error):
			Log.error("progress action \(currentActionName ?? "unknown") failed: \(error)", .app)
			progressObserver.send(value: ProgressUpdate(.failed, message: currentActionName, error: error))
		case .interrupted:
			progressObserver.send(value: ProgressUpdate(.completed, message: "\(currentActionName ?? "operation") canceled"))
		case .completed:
			Log.info("progress action \(currentActionName ?? "unknown") completed", .app)
			progressObserver.send(value: ProgressUpdate(.completed, message: "\(currentActionName ?? "operation") completed"))
		}
		if ended {
			busyObserver.send(value: false)
			_statusQueue.sync { _currentDisposable = nil }
		}
	}
	
	/// Displays information about error to the user document-modal if session has an associated window, app-modal otherwise
	///
	/// - Parameters:
	///   - error: the error to inform the user about
	///   - session: the session this error is related to
	func presentError(_ error: Rc2Error, session: Session?) {
		let alert = NSAlert()
		alert.messageText = error.localizedDescription
		alert.informativeText = error.nestedError?.localizedDescription ?? ""
		alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
		if let parentWindow = getWindow(session) {
			alert.beginSheetModal(for: parentWindow, completionHandler:nil)
		} else {
			alert.runModal()
		}
	}
	
	/// Displays an alert to the user document-modal if session has an associated window, app-modal otherwise
	///
	/// - Parameters:
	///   - session: the session this alert is related to
	///   - message: the message to display
	///   - details: the details of the message
	///   - buttons: array of button names, defaults to only showing an OK button
	///   - defaultButtonIndex: the index of the button that is made the default button
	///   - isCritical: true if alert is critical
	///   - queue: the queue to call the handler on, defaults to main queue
	///   - handler: closure called returning the index of the button clicked by the user
	func presentAlert(_ session: Session?, message: String, details: String, buttons: [String] = [], defaultButtonIndex: Int = 0, isCritical: Bool = false, queue: DispatchQueue = .main, handler: ((NSApplication.ModalResponse) -> Void)?)
	{
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = details
		if buttons.count == 0 {
			alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
		} else {
			for aButton in buttons {
				alert.addButton(withTitle: aButton)
			}
		}
		alert.alertStyle = isCritical ? .critical : .warning
		if let parentWindow = getWindow(session) {
			alert.beginSheetModal(for: parentWindow, completionHandler: { (rsp) in
				// makes no sense. why isn't the handler going to be called if there is only a default button?
				// guard buttons.count > 1 else { return }
				alert.window.orderOut(nil)
				queue.async {
					//convert rsp to an index to buttons
					handler?(rsp)
				}
			})
		} else {
			handler?(alert.runModal())
		}
	}
}

extension SignalProducer where Error == Rc2Error {
	/// have status observe progress from this event stream
	///
	/// - Parameters:
	///   - status: the AppStatus object to observe the event stream
	///   - actionName: a name for the action taking place, displayed to the user along with " completed" or " canceled"
	///   - converter: a closure that converts an event stream value to a ProgressUpdate?. Defaults to returning nil which will ignore any value events
	/// - Returns: self with status attached as an observer
	func updateProgress(status: MacAppStatus?, actionName: String, determinate: Bool = false, converter: ((Value) -> ProgressUpdate?)? = nil) -> SignalProducer<Value, Error>
	{
		guard let status = status else { return self }
		Log.debug("updateProgress called", .app)
		var actualConverter = converter
		// if no converter is supplied, and the value type is a progress update, just pass it along if it is a value event
		if nil == actualConverter, Value.self == ProgressUpdate.self {
			actualConverter = { (prog) -> ProgressUpdate? in
				guard let pv = prog as? ProgressUpdate, pv.stage == .value else { return nil }
				return pv
			}
		}
		return SignalProducer<Value, Error> { observer, compositeDisposable in
			self.startWithSignal { signal, disposable in
				Log.debug("status action starting \(actionName)", .app)
				status.actionStarting(name: actionName, disposable: disposable, determinate: determinate)
				compositeDisposable += disposable
				compositeDisposable += signal
					.on(event: { (original) in
						switch original {
						case .completed:
							status.process(Signal<ProgressUpdate, Rc2Error>.Event.completed)
						case .interrupted:
							status.process(Signal<ProgressUpdate, Rc2Error>.Event.interrupted)
						case .failed(let err):
							status.process(Signal<ProgressUpdate, Rc2Error>.Event.failed(err))
						case .value(let val):
							Log.debug("status is processing", .app)
							if let convertedValue = actualConverter?(val) {
								status.process(Signal<ProgressUpdate, Rc2Error>.Event.value(convertedValue))
							}
						}
					}).observe(on: UIScheduler())
					.observe(observer)
			}
		}
	}
}
