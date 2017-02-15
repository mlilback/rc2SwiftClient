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
}

extension NSTabViewController {
	var currentTabItemViewController: NSViewController {
		return tabViewItems[selectedTabViewItemIndex].viewController!
	}
}
