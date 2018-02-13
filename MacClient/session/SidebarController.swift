//
//  SidebarController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

fileprivate extension NSStoryboard.SceneIdentifier {
	static let sidebarTabController = NSStoryboard.SceneIdentifier("sidebarTabController")
}

class SidebarController: NSViewController {
	@IBOutlet var contentView: NSView!
	var tabController: SidebarTabController!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let sboard = NSStoryboard(name: .mainController, bundle: nil)
		// for some reason won't compile if directly setting tabController
		let controller: SidebarTabController = embedViewController(storyboard: sboard, identifier: .sidebarTabController, contentView: contentView)
		tabController = controller
	}
}
