//
//  ThemePrefsController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import ClientCore
import SwiftyUserDefaults
import Networking

class ThemePrefsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet private var tabView: NSTabView!
	@IBOutlet private var syntaxButton: NSButton!
	@IBOutlet private var outputButton: NSButton!
	
	private var outputEditor: ThemeEditorController<OutputTheme>?
	private var syntaxEditor: ThemeEditorController<SyntaxTheme>?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		
		// FIXME: why are these using hardcoded paths instead of pulling from Theme/ThemeManager?
		if outputEditor == nil {
			let bundle = Bundle(for: OutputTheme.self)
			let builtin = bundle.url(forResource: "OutputThemes", withExtension: "json")!
			// swiftlint:disable:next force_try
			let user = try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: "OutputThemes")
			outputEditor = ThemeEditorController<OutputTheme>.createInstance(userUrl: user, builtinUrl: builtin)
			tabView.tabViewItem(at: 0).view = outputEditor!.view
		}
		if syntaxEditor == nil {
			let bundle = Bundle(for: SyntaxTheme.self)
			let builtin = bundle.url(forResource: "SyntaxThemes", withExtension: "json")!
			// swiftlint:disable:next force_try
			let user = try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: "SyntaxThemes")
			syntaxEditor = ThemeEditorController<SyntaxTheme>.createInstance(userUrl: user, builtinUrl: builtin)
			tabView.tabViewItem(at: 1).view = syntaxEditor!.view
			switchEditor(syntaxButton)
		}
	}
	
	@IBAction func switchEditor(_ sender: Any?) {
		guard let button = sender as? NSButton else { return }
		let syntaxClicked = button == syntaxButton
		syntaxButton.state = !syntaxClicked ? .off : .on
		outputButton.state = !syntaxClicked ? .on : .off
		syntaxButton.isEnabled = !syntaxClicked
		outputButton.isEnabled = syntaxClicked
		tabView.selectTabViewItem(at: syntaxClicked ? 1 : 0)
//		assert(syntaxButton.state != outputButton.state)
	}
}
