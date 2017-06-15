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
	@IBOutlet private var tabView: NSTabView!
	@IBOutlet private var syntaxButton: NSButton!
	@IBOutlet private var outputButton: NSButton!
	
	private var outputEditor: ThemeEditorController<OutputTheme>?
	private var syntaxEditor: ThemeEditorController<SyntaxTheme>?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let blueAttrs: [NSAttributedStringKey: Any] = [.foregroundColor: NSColor.blue, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
		let blackAttrs: [NSAttributedStringKey: Any] = [.foregroundColor: NSColor.black, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
		syntaxButton.attributedTitle = NSAttributedString(string: syntaxButton.title, attributes: blueAttrs)
		syntaxButton.attributedAlternateTitle = NSAttributedString(string: syntaxButton.title, attributes: blackAttrs)
		outputButton.attributedTitle = NSAttributedString(string: outputButton.title, attributes: blueAttrs)
		outputButton.attributedAlternateTitle = NSAttributedString(string: outputButton.title, attributes: blackAttrs)
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		
		if outputEditor == nil {
			let builtin = Bundle.main.url(forResource: "outputThemes", withExtension: "json")!
			// swiftlint:disable:next force_try
			let user = try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: "OutputThemes")
			outputEditor = ThemeEditorController<OutputTheme>.createInstance(userUrl: user, builtinUrl: builtin)
			tabView.tabViewItem(at: 0).view = outputEditor!.view
		}
		if syntaxEditor == nil {
			let builtin = Bundle.main.url(forResource: "syntaxThemes", withExtension: "json")!
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
		syntaxButton.state = syntaxClicked ? .offState : .onState
		outputButton.state = syntaxClicked ? .onState : .offState
		syntaxButton.isEnabled = !syntaxClicked
		outputButton.isEnabled = syntaxClicked
		tabView.selectTabViewItem(at: syntaxClicked ? 1 : 0)
	}
}
