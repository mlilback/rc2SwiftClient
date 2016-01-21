//
//  MacSessionController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

public class MacSessionController: NSViewController, ToolbarItemHandler {
	var sessionView: MacSessionView?
	var outputController: MacSessionOutputController?
	var editController: MacSessionEditorController?
	var leftController: MacSessionMultiController?
	var segmentItem: NSToolbarItem?
	var segmentControl: NSSegmentedControl?
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		sessionView = view as? MacSessionView
		//create refs to our child controllers
		for aController in childViewControllers {
			if aController is MacSessionOutputController {
				outputController = (aController as! MacSessionOutputController)
			} else if aController is MacSessionEditorController {
				editController = (aController as! MacSessionEditorController)
			} else if aController is MacSessionMultiController {
				leftController = (aController as! MacSessionMultiController)
			}
		}
		NSNotificationCenter.defaultCenter().addObserverForName(SelectedSessionChangedNotification, object: nil, queue: nil) { (note) -> Void in
			let wspace = note.object as! Box<Workspace>
			print("got workspace: \(wspace.unbox.name)")
		}
	}

	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "leftView" {
			segmentItem = item
			segmentControl = item.view as! NSSegmentedControl?
			segmentControl?.target = self
			segmentControl?.action = "tabSwitcherClicked:"
			let lastSelection = NSUserDefaults.standardUserDefaults().integerForKey(leftController!.LastSelectionKey)
			segmentControl?.selectedSegment = lastSelection
			leftController?.selectTabAtIndex(lastSelection)
			return true
		}
		return false
	}
	
	dynamic func tabSwitcherClicked(sender:AnyObject?) {
		let index = (segmentControl?.selectedSegment)!
		if index == leftController?.selectedTabIndex {
			//same as currently selected. toggle visibility
			sessionView?.toggleLeftView(sender)
			segmentControl?.setSelected(!sessionView!.leftViewVisible, forSegment: index)
		} else {
			if !(sessionView!.leftViewVisible) {
				sessionView?.toggleLeftView(sender)
			}
			segmentControl?.setSelected(true, forSegment: index)
			leftController?.selectTabAtIndex(index)
			NSUserDefaults.standardUserDefaults().setInteger(index, forKey: leftController!.LastSelectionKey)
		}
	}
	
}

