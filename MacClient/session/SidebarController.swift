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
	weak var tabController: SidebarTabController!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let sboard = NSStoryboard(name: .mainController, bundle: nil)
		tabController = sboard.instantiateController(withIdentifier: .sidebarTabController) as! SidebarTabController
		self.addChildViewController(tabController)
		contentView.addSubview(tabController.view)
		tabController.view.translatesAutoresizingMaskIntoConstraints = false
		tabController.view.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
		tabController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
		tabController.view.leftAnchor.constraint(equalTo: contentView.leftAnchor).isActive = true
		tabController.view.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true
	}
}
