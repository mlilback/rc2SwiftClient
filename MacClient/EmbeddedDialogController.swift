//
//  EmbeddedDialogController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

protocol EmbeddedDialogController {
	var canContinue: Bool { get }
	
	func continueAction(_ callback: @escaping (_ value: Any?, _ error: Rc2Error?) -> Void)
}
