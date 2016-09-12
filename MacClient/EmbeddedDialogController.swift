//
//  EmbeddedDialogController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol EmbeddedDialogController {
	var canContinue:Bool { get }
	
	func continueAction(_ callback: @escaping (_ value:Any?, _ error:NSError?) -> Void)
}
