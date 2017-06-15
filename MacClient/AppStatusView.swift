//
//  AppStatusView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Result
import ReactiveSwift

let messageTimeout: DispatchTimeInterval = .seconds(3)
let messageLeeway: DispatchTimeInterval = .milliseconds(10)

fileprivate struct TimerAction {
	let timer: DispatchSourceTimer
	init(interval: DispatchTimeInterval, queue: DispatchQueue, action: @escaping () -> Void) {
		timer = DispatchSource.makeTimerSource(queue: queue)
		timer.setEventHandler(handler: action)
		timer.scheduleOneshot(deadline: .now() + interval, leeway: messageLeeway)
		timer.resume()
	}
}

class AppStatusView: NSView {
	@IBOutlet var textField: NSTextField?
	@IBOutlet var progress: NSProgressIndicator?
	@IBOutlet var determinateProgress: NSProgressIndicator?
	@IBOutlet var cancelButton: NSButton?

	fileprivate var progressDisposable: Disposable?
	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.appStatusQueue", qos: .userInitiated)
	private var clearTimer: TimerAction?

	weak var appStatus: MacAppStatus? { didSet {
		progressDisposable?.dispose()
		progressDisposable = appStatus?.progressSignal.observe(on: UIScheduler()).observeValues(observe)
	} }
	
	override var intrinsicContentSize: NSSize { return NSSize(width:220, height:22) }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		clearStatus()
	}
	
	fileprivate func clearStatus() {
		DispatchQueue.main.async {
			self.progressDisposable = nil
			self.clearTimer = nil
			self.cancelButton?.isEnabled = false
			self.cancelButton?.isHidden = true
			self.textField?.stringValue = ""
			self.progress?.isHidden = true
			self.determinateProgress?.isHidden = true
		}
	}
	
	/// called when a progress update received
	fileprivate func observe(update: ProgressUpdate) {
		switch update.stage {
		case .start:
			handleStart(update)
		case .completed, .failed:
			handleCompleted(update)
		case .value:
			handleValue(update)
		}
	}
	
	fileprivate func handleStart(_ update: ProgressUpdate) {
		_statusQueue.sync {
			if update.value == -1 {
				progress?.isHidden = false
				determinateProgress?.isHidden = true
				progress?.startAnimation(self)
			} else {
				progress?.isHidden = true
				determinateProgress?.isHidden = false
				determinateProgress?.doubleValue = update.value
				textField?.stringValue = update.message ?? "Starting action…"
			}
		}
	}
	
	fileprivate func handleCompleted(_ update: ProgressUpdate) {
		_statusQueue.sync {
			clearStatus()
			textField?.stringValue = update.message ?? ""
			self.clearTimer = TimerAction(interval: messageTimeout, queue: _statusQueue) { [weak self] in
				self?.clearStatus()
			}
		}
	}

	fileprivate func handleValue(_ update: ProgressUpdate) {
		_statusQueue.sync {
			if update.value >= 0 {
				determinateProgress?.doubleValue = update.value
			}
			if let msg = update.message {
				textField?.stringValue = msg
			}
		}
	}
	
	@IBAction func cancel(_ sender: AnyObject?) {
		
	}

	override func draw(_ dirtyRect: NSRect) {
		NSGraphicsContext.current?.saveGraphicsState()
		let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
		path.addClip()
		NSColor.white.setFill()
		path.fill()
		NSColor.black.set()
		path.stroke()
		NSGraphicsContext.current?.restoreGraphicsState()
		super.draw(dirtyRect)
	}
}
