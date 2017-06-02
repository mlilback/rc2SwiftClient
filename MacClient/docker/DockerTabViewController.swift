//
//  DockerTabViewController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Docker

class DockerTabViewController: NSTabViewController {
	var manager: DockerManager?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		tabViewItems.forEach {
			guard let vc = $0.viewController as? DockerManagerInjectable else { return }
			vc.manager = manager
		}
	}
}
