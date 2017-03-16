//
//  ThemePrefsController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import ClientCore
import os
import SwiftyUserDefaults
import Networking

class ThemePrefsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	private var outputEditor: ThemeEditorController<OutputTheme>?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		
		if outputEditor == nil {
			let builtin = Bundle.main.url(forResource: "outputThemes", withExtension: "json")!
			// swiftlint:disable:next force_try
			let user = try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: "OutputThemes")
			outputEditor = ThemeEditorController<OutputTheme>.createInstance(userUrl: user, builtinUrl: builtin)
			view.addSubview(outputEditor!.view)
		}
	}
}
