//
//  WorkspacesViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc class WorkspacesViewController : NSViewController, NSTableViewDelegate
{
	@IBOutlet weak var wspacesTableView: NSTableView?
	@IBOutlet weak var segments: NSSegmentedControl?
	@IBOutlet var arrayController: NSArrayController?
	@IBOutlet var okButton: NSButton?
	
	dynamic var workspaces: [String]?
	dynamic var selectedWorkspace : String?
	var actionCallback: ((controller:WorkspacesViewController, workspaceName:String) -> ())?
	
	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
	
	override func viewWillAppear() {
		super.viewWillAppear();
		workspaces = RestServer.sharedInstance.loginSession!.workspaces.map({$0.name})
		selectedWorkspace = workspaces?.first
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		view.window?.performSelectorOnMainThread(#selector(NSWindow.makeFirstResponder(_:)), withObject: okButton, waitUntilDone: false)
	}
	
	@IBAction func segButtonClicked(sender:AnyObject?) {
		if segments?.selectedSegment == 0 {
			//add workspace
		} else {
			//delete workspace
		}
	}
	
	@IBAction func selectWorkspace(sender:AnyObject?) {
		let wspace = RestServer.sharedInstance.loginSession!.workspaceWithName(selectedWorkspace!)!
		NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(SelectedWorkspaceChangedNotification, object: Box(wspace))
		actionCallback?(controller: self, workspaceName: selectedWorkspace!)
	}
	
	func tableViewSelectionDidChange(notification: NSNotification) {
		let row = (wspacesTableView?.selectedRow)!
		if row == -1 {
			selectedWorkspace = nil
		} else {
			selectedWorkspace = workspaces?[row]
		}
		segments?.setEnabled(selectedWorkspace != nil, forSegment: 1)
	}
}
