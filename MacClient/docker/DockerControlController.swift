//
//  DockerControlController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Docker

class DockerControlController: DockerManagerInjectable {
	var tableController: DockerContainerController?
	@IBOutlet private var startButton: NSButton!
	@IBOutlet private var stopButton: NSButton!
	@IBOutlet private var pauseButton: NSButton!
	@IBOutlet private var resumeButton: NSButton!
	@IBOutlet private var restartButton: NSButton!
	private var buttonArray: [NSButton]!

	override public func awakeFromNib() {
		super.awakeFromNib()
		buttonArray = [startButton, stopButton, restartButton, pauseButton, resumeButton]
	}
	
	override public func viewWillAppear() {
		super.viewWillAppear()
		guard let manager = manager else { fatalError("no docker manager set") }
		tableController = firstChildViewController(self)
		for container in manager.containers {
			container.state.signal.observeValues { [weak self] _ in
				self?.adjustControls()
			}
		}
		_ = tableController?.selectedContainer.signal.observeValues({ [weak self] _ in
			self?.adjustControls()
		})
	}
	
	func adjustControls() {
		buttonArray.forEach { $0.isEnabled = false }
		guard let selection = tableController?.selectedContainer, let state = selection.value?.state.value else { return }
		switch state {
		case .notAvailable:
			return
		case .paused:
			resumeButton?.isEnabled = true
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
