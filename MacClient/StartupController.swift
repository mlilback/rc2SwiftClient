//
//  StartupController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import ClientCore
import DockerSupport

public enum SetupStage {
	case initial
	case docker
	case localLogin
	case restoreSessions
	case complete
}

public class StartupController: NSViewController {
	@IBOutlet fileprivate dynamic var progressBar: NSProgressIndicator?
	@IBOutlet fileprivate dynamic var statusText: NSTextField?
	/// the current stage of the setup process
	public var stage: SetupStage = .initial { didSet { stateChanged() } }
	/// the current progress while in the .docker state
	public var pullProgress: PullProgress? { didSet { updatePullProgress() } }
	/// the status message being displayed
	public var statusMesssage: String {
		get { return statusText?.stringValue ?? "" }
		set { statusText?.stringValue = newValue }
	}
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		//setup initial state
		stateChanged()
	}

	private func updatePullProgress() {
		let percent = Double(pullProgress!.currentSize) / Double(pullProgress!.estSize)
		progressBar?.doubleValue = percent
		if pullProgress!.extracting {
			statusText?.stringValue = "Extracting…"
		} else {
			statusText?.stringValue = "Downloading…"
		}
	}
	
	private func stateChanged() {
		switch stage {
		case .initial:
			statusMesssage = "Initializing…"
			progressBar?.isIndeterminate = true
		case .docker:
			statusMesssage = "Setting up Docker…"
			progressBar?.isIndeterminate = false
			progressBar?.doubleValue = 0
		case .localLogin:
			progressBar?.isIndeterminate = true
			statusMesssage = "Connecting to server…"
		case .restoreSessions:
			progressBar?.isIndeterminate = true
			statusMesssage = "Restoring open sessions…"
		case .complete:
			statusMesssage = "Startup Complete"
		}
	}
}

/// needed for easy instantiation from storyboard
public class StartupWindowController: NSWindowController {
}
