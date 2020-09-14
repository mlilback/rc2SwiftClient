//
//  GeneralPrefsController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyUserDefaults

class GeneralPrefsController: NSViewController {

	@IBAction func resetWarnings(_ sender: Any?) {
		DefaultsKeys.suppressKeys.forEach { UserDefaults.standard.remove($0) }
	}
}
