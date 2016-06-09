//
//  NSViewController+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSViewController {
	func responderChainContains(responder:NSResponder) -> Bool {
		var curResponder = view.window?.firstResponder
		while curResponder != nil {
			if curResponder == responder { return true }
			curResponder = curResponder?.nextResponder
		}
		return false
	}
}