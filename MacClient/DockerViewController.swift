//
//  DockerViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore


public class DockerViewController: NSViewController {
	dynamic var manager: DockerManager? { didSet {
		manager?.refreshContainers().onSuccess { _ in
			self.tableController?.manager = self.manager
			self.tableController?.containerTable?.reloadData()
		}
	} }
	dynamic var tableController: DockerContainerController?
	
	override public func viewDidLoad() {
		super.viewDidLoad()
	}
	
	override public func viewWillAppear() {
		super.viewWillAppear()
		tableController = firstChildViewController(self)
		tableController?.manager = manager
	}
	
	@IBAction func startSelection(_ sender: AnyObject) {
	}

	@IBAction func stopSelection(_ sender: AnyObject) {
	}

	@IBAction func restartSelection(_ sender: AnyObject) {
	}

	@IBAction func pauseSelection(_ sender: AnyObject) {
	}

	@IBAction func resumeSelection(_ sender: AnyObject) {
	}
}

