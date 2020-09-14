//
//  StartupController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common

public enum SetupStage {
	case initial
	case downloading
	case localLogin
	case restoreSessions
	case complete
}

public class StartupController: NSViewController {
	@IBOutlet fileprivate dynamic var progressBar: NSProgressIndicator!
	@IBOutlet fileprivate dynamic var statusText: NSTextField!
	/// the current stage of the setup process
	public var stage: SetupStage = .initial { didSet { stateChanged() } }
	/// the current progress while in the .docker state
//	public var pullProgress: PullProgress? { didSet { updatePullProgress() } }
	/// the status message being displayed
	public var statusMesssage: String {
		get { return statusText.stringValue }
		set { statusText.stringValue = newValue }
	}

	public func updateStatus(message: String) {
		guard Thread.isMainThread else {
			DispatchQueue.main.async { self.stateChanged() }
			return
		}
		statusText.stringValue = message
	}

	override public func viewDidLoad() {
		super.viewDidLoad()
		progressBar.usesThreadedAnimation = true
		//setup initial state
		stateChanged()
	}

	private var lastPercent: Double = 0

//	private func updatePullProgress() {
//		let percent = Double(pullProgress!.currentSize) / Double(pullProgress!.estSize)
//		lastPercent = percent
//		progressBar.doubleValue = percent
////		print("per=\(percent), cs=\(pullProgress!.currentSize) est=\(pullProgress!.estSize)")
//		if pullProgress!.extracting {
//			statusText.stringValue = "Extracting…"
//		} else {
//			statusText.stringValue = "Downloading \(pullProgress!.name)…"
//		}
//	}

	private func stateChanged() {
		guard Thread.isMainThread else {
			DispatchQueue.main.async { self.stateChanged() }
			return
		}
		switch stage {
		case .initial:
			statusMesssage = "Initializing…"
			progressBar.isIndeterminate = true
			progressBar.startAnimation(self)
		case .downloading:
			statusMesssage = "Downloading…"
			progressBar.stopAnimation(nil)
			progressBar.isIndeterminate = false
			progressBar.doubleValue = 0
		case .localLogin:
			progressBar.doubleValue = 0
			progressBar.isIndeterminate = true
			progressBar.startAnimation(self)
			statusMesssage = "Connecting to server…"
		case .restoreSessions:
			progressBar.isIndeterminate = true
			statusMesssage = "Restoring open sessions…"
		case .complete:
			progressBar.stopAnimation(self)
			statusMesssage = "Startup Complete"
		}
	}
}

/// needed for easy instantiation from storyboard
public class StartupWindowController: NSWindowController {
}
