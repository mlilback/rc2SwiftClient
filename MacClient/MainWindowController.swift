//
//  MainWindowController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MainWindowController: NSWindowController, ToolbarDelegatingOwner, NSToolbarDelegate {
	///Object that lets us monitor the status of the application. Nededed to pass on to the statusView once setup is finished
	dynamic weak var appStatus: AppStatus?
	
	weak var session: Session?
	
	///Custom view that shows the status of the application: progress, message, cancel button
	var statusView: AppStatusView?
	
	/// Need to schedule setting up toolbar handlers, but don't want to do it more than once
	private var toolbarSetupScheduled = false
	
	class func createFromNib() -> Self {
		let winc = self.init(windowNibName: "MainWindow")
		return winc
	}
	
	override func windowDidLoad() {
		super.windowDidLoad()
		window!.titleVisibility = .Hidden
	}
	
	func setupChildren(restServer:RestServer) {
		statusView?.appStatus = appStatus
		let rootVC = contentViewController as! RootViewController
		rootVC.restServer = restServer
		rootVC.sessionClosedHandler = {
			dispatch_async(dispatch_get_main_queue()) {
				self.window?.close()
			}
		}
		let viewControllers = recursiveFlatMap(rootVC, transform: { $0 as? AbstractSessionViewController }, children: { $0.childViewControllers })
		for aController in viewControllers {
			aController.sessionOptional = restServer.session
		}
	}

	//When the first toolbar item is loaded, queue a closure to call assignHandlers from the ToolbarDelegatingOwner protocol(default implementation) that assigns each toolbar item to the appropriate ToolbarItemHandler (normally a view controller)
	func toolbarWillAddItem(notification: NSNotification) {
		//schedule assigning handlers after toolbar items are loaded
		if !toolbarSetupScheduled {
			dispatch_async(dispatch_get_main_queue()) { () -> Void in
				self.assignHandlers(self.contentViewController!, items: (self.window?.toolbar?.items)!)
			}
			toolbarSetupScheduled = true
		}
		let item:NSToolbarItem = (notification.userInfo!["item"] as? NSToolbarItem)!
		if item.itemIdentifier == "status",
			let sview = item.view as? AppStatusView
		{
			statusView = sview
		}
	}
}
