//
//  ProjectManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

public class ProjectManager: NSViewController, EmbeddedDialogController {
	@IBOutlet var projectOutline:NSOutlineView?
	@IBOutlet var addRemoveButtons:NSSegmentedControl?
	
	dynamic var canContinue:Bool = false

	func continueAction(callback:(value:Any?, error:NSError?) -> Void) {
		callback(value: nil, error: NSError(domain: Rc2ErrorDomain, code: 111, userInfo: [NSLocalizedDescriptionKey:"project selection not implemented"]))
	}
	
	@IBAction func addRemoveAction(sender:AnyObject?) {
		
	}
	
}

