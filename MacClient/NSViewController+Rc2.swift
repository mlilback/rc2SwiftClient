//
//  NSViewController+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSViewController {
	func responderChainContains(_ responder: NSResponder?) -> Bool {
		guard let responder = responder else { return false }
		var curResponder = view.window?.firstResponder
		while curResponder != nil {
			if curResponder == responder { return true }
			curResponder = curResponder?.nextResponder
		}
		return false
	}

	/// Loads a view controller from a storyboard, adds it as a child view controller, and embeds it's view in contentView
	///
	/// - Parameters:
	///   - storyboard: the storyboard to load the child controller from
	///   - identifier: the identifier of the child controller
	///   - contentView: the view to embed the child controller's view into
	/// - Returns: the loaded child controller
	func embedViewController<ControllerType: NSViewController>(storyboard: NSStoryboard, identifier: NSStoryboard.SceneIdentifier, contentView: NSView) -> ControllerType
	{
		guard let childController = storyboard.instantiateController(withIdentifier: identifier) as? ControllerType
			else { fatalError("failed to load \(identifier)") }
		addChild(childController)
		let childView = childController.view
		contentView.addSubview(childView)
		childView.translatesAutoresizingMaskIntoConstraints = false
		childView.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
		childView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
		childView.leftAnchor.constraint(equalTo: contentView.leftAnchor).isActive = true
		childView.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true
		return  childController
	}
}

extension NSTabViewController {
	var currentTabItemViewController: NSViewController {
		return tabViewItems[selectedTabViewItemIndex].viewController!
	}
}
