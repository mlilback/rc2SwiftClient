//
//  MacAppConstants.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSStoryboard.Name {
	static let mainBoard = NSStoryboard.Name(rawValue: "Main")
	static let mainController = NSStoryboard.Name(rawValue: "MainController")
}

extension NSStoryboard.SceneIdentifier {
	static let logWindowController = NSStoryboard.SceneIdentifier(rawValue: "LogWindowController")
}

extension NSUserInterfaceItemIdentifier {
	static let sessionWindow = NSUserInterfaceItemIdentifier(rawValue: "session")
	static let logWindow = NSUserInterfaceItemIdentifier(rawValue: "logWindow")
	static let dockerWindow = NSUserInterfaceItemIdentifier(rawValue: "dockerWindow")
}

struct Resources {
	static let fileTemplateDirName = "FileTemplates"
}
