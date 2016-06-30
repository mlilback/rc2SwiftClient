//
//  ProjectManagerViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class ProjectWrapper: NSObject {
	static func wrappersForProjects(projects:[Project]) -> [ProjectWrapper] {
		var wrappers = [ProjectWrapper]()
		for aProject in projects {
			wrappers.append(ProjectWrapper(project: aProject))
		}
		return wrappers
	}
	
	var project:Project
	var workspaces:[Box<Workspace>]
	init(project:Project) {
		self.project = project
		self.workspaces = []
		super.init()
		for aWorkspace in project.workspaces {
			workspaces.append(Box(aWorkspace))
		}
	}
}

public class ProjectManagerViewController: NSViewController, EmbeddedDialogController {
	@IBOutlet var projectOutline:NSOutlineView?
	@IBOutlet var addRemoveButtons:NSSegmentedControl?
	
	dynamic var canContinue:Bool = false
	private var projectWrappers:[ProjectWrapper] = []
	
	var host:ServerHost?
	var loginSession:LoginSession? { didSet { projectWrappers = ProjectWrapper.wrappersForProjects(loginSession!.projects) } }

	override public func viewWillAppear() {
		super.viewWillAppear()
		projectOutline?.expandItem(nil, expandChildren: true)
	}
	
	override public func viewDidAppear() {
		super.viewDidAppear()
		projectOutline?.reloadData()
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
			return projectWrappers.count
		}
		return 0
	}
	
	public func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
		return item is ProjectWrapper
	}
	
	public func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
		if let proj = item as? ProjectWrapper {
			return proj.workspaces.count
		}
		return projectWrappers[index]
	}
	
	public func outlineView(outlineView: NSOutlineView, objectValueForTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) -> AnyObject?
	{
		if let proj = item as? ProjectWrapper {
			return proj.project.name
		} else if let wspace = item as? Box<Workspace> {
			return wspace.unbox.name
		}
		return nil
	}
}
