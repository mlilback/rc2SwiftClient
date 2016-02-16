//
//  MainWindowController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MainWindowController: NSWindowController, ToolbarDelegatingOwner, NSToolbarDelegate {
	@IBOutlet var rootTabController: NSTabViewController?
	dynamic var appStatus: AppStatus?
	var statusView: AppStatusView?
	
	private var toolbarSetupScheduled = false
	
	override func windowDidLoad() {
		super.windowDidLoad()
		window!.titleVisibility = .Hidden
	}
	
	func setupChildren() {
		statusView?.appStatus = appStatus
		rootTabController = firstRecursiveDescendent(contentViewController!,
			children: { $0.childViewControllers },
			filter: { $0 is NSTabViewController })  as? NSTabViewController
		showWorkspaceSelectTab()
		let workspacesVC = firstRecursiveDescendent(rootTabController!, children: {$0.childViewControllers}, filter: {$0 is WorkspacesViewController}) as! WorkspacesViewController
		dispatch_async(dispatch_get_main_queue(), {
			workspacesVC.actionCallback = { (controller:WorkspacesViewController, workspaceName:String) in
				self.showSessionTab()
				self.window!.title = String.localizedStringWithFormat(NSLocalizedString("WindowTitleFormat", comment: ""), workspaceName)
			}
		})
	}
	
	func showWorkspaceSelectTab() {
		rootTabController?.selectedTabViewItemIndex = (rootTabController?.tabView.indexOfTabViewItemWithIdentifier("workspaceSelect"))!
		let progress = NSProgress(totalUnitCount: 1) {
			self.appStatus!.updateStatus(nil)
			NSBeep()
		}
		progress.localizedDescription = "selecting workspace…"
	}
	
	func showSessionTab() {
		let sessionIndex = (rootTabController?.tabView.indexOfTabViewItemWithIdentifier("session"))!
		dispatch_async(dispatch_get_main_queue(), {
			self.rootTabController?.selectedTabViewItemIndex = sessionIndex
			self.appStatus?.updateStatus(nil)
		})
	}
	
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
