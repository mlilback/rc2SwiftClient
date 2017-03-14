//
//  DockerViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import DockerSupport

public class DockerViewController: NSViewController {
	dynamic var manager: DockerManager? { didSet {
		self.tableController?.manager = self.manager
		self.tableController?.containerTable?.reloadData()
	} }
	dynamic var tableController: DockerContainerController?
	@IBOutlet dynamic var startButton: NSButton?
	@IBOutlet dynamic var stopButton: NSButton?
	@IBOutlet dynamic var pauseButton: NSButton?
	@IBOutlet dynamic var unpauseButton: NSButton?
	@IBOutlet dynamic var restartButton: NSButton?
	var buttonArray: [NSButton]!
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		buttonArray = [startButton!, stopButton!, restartButton!, pauseButton!, unpauseButton!]
	}
	
	override public func viewWillAppear() {
		super.viewWillAppear()
		tableController = firstChildViewController(self)
		tableController?.manager = manager
		for container in manager!.containers {
			container.state.signal.observeValues { [weak self] _ in
				self?.adjustControls()
			}
		}
		_ = tableController?.selectedContainer.signal.observeValues({ [weak self] _ in
			self?.adjustControls()
		})
	}
	
	func disableAllButtons() {
		for aButton in buttonArray {
			aButton.isEnabled = false
		}
	}
	
	func adjustControls() {
		disableAllButtons()
		guard let selection = tableController?.selectedContainer, let state = selection.value?.state.value else { return }
		switch state {
			case .notAvailable:
				return
			case .paused:
				unpauseButton?.isEnabled = true
			case .exited, .created:
				startButton?.isEnabled = true
			case .restarting:
				stopButton?.isEnabled = true
			case .running:
				stopButton?.isEnabled = true
				pauseButton?.isEnabled = true
				restartButton?.isEnabled = true
		}
	}
	
	func selectedContainer() -> DockerContainer {
		guard let container = tableController?.selectedContainer.value else { fatalError("have a container with no state") }
		return container
	}
	
	@IBAction func startSelection(_ sender: AnyObject) {
		manager?.perform(operation: .start, on: selectedContainer()).startWithFailed { error in
			print("failed to start: \(error)")
		}
	}

	@IBAction func stopSelection(_ sender: AnyObject) {
		manager?.perform(operation: .stop, on: selectedContainer()).startWithFailed { error in
			print("failed to stop: \(error)")
		}
	}

	@IBAction func restartSelection(_ sender: AnyObject) {
		manager?.perform(operation: .restart, on: selectedContainer()).startWithFailed { error in
			print("failed to restart: \(error)")
		}
	}

	@IBAction func pauseSelection(_ sender: AnyObject) {
		manager?.perform(operation: .pause, on: selectedContainer()).startWithFailed { error in
			print("failed to pause: \(error)")
		}
	}

	@IBAction func resumeSelection(_ sender: AnyObject) {
		manager?.perform(operation: .resume, on: selectedContainer()).startWithFailed { error in
			print("failed to resume: \(error)")
		}
	}
}
