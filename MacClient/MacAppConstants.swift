//
//  MacAppConstants.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSStoryboard.Name {
	static let mainBoard = "Main"
	static let mainController = "MainController"
	static let prefs = "Preferences"
}

extension NSStoryboard.SceneIdentifier {
	static let logWindowController = "LogWindowController"
}

extension NSUserInterfaceItemIdentifier {
	static let sessionWindow = NSUserInterfaceItemIdentifier(rawValue: "session")
	static let logWindow = NSUserInterfaceItemIdentifier(rawValue: "logWindow")
}

struct Resources {
	static let fileTemplateDirName = "FileTemplates"
}

struct Notebook {
	static let textEditorMargin: CGFloat = 6
}
