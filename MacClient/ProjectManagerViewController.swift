//
//  ProjectManagerViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

public class ProjectManagerViewController: NSViewController, EmbeddedDialogController {
	@IBOutlet var projectOutline:NSOutlineView?
	@IBOutlet var addRemoveButtons:NSSegmentedControl?
	
	dynamic var canContinue:Bool = false
	
	var host:ServerHost?
	var loginSession:LoginSession?

	override public func viewDidAppear() {
		super.viewDidAppear()
		projectOutline?.reloadData()
		projectOutline?.expandItem(nil, expandChildren: true)
	}
	
	func continueAction(callback:(value:Any?, error:NSError?) -> Void) {
		callback(value: nil, error: NSError(domain: Rc2ErrorDomain, code: 111, userInfo: [NSLocalizedDescriptionKey:"project selection not implemented"]))
	}
	
	@IBAction func addRemoveAction(sender:AnyObject?) {
		
	}
}

extension ProjectManagerViewController: NSOutlineViewDataSource {
	
	public func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
		if nil == item {
			return loginSession?.projects.count ?? 0
		} else if let proj = item as? Project {
			return proj.workspaces.count
		}
		return 0
	}
	
	public func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
		return item is Project
	}
	
	public func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
		if let proj = item as? Project {
			return proj.workspaces[index]
		}
		return loginSession!.projects[index]
	}
}

extension ProjectManagerViewController: NSOutlineViewDelegate {
	public func outlineView(outlineView: NSOutlineView, viewForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSView?
	{
		var val = "";
		if let proj = item as? Project {
			val = proj.name
		} else if let wspace = item as? Workspace {
			val = wspace.name
		}
		let view = outlineView.makeViewWithIdentifier("string", owner: nil) as? NSTableCellView
		view?.textField?.stringValue = val
		return view
	}
}
