//
//  EditorContext.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import Networking
import ReactiveSwift
import SyntaxParsing

public enum EditorMode: Int {
	case source = 0
	case preview
}

public protocol CodeEditor: class {
	var canExecute: Bool { get }
	func setContext(context: EditorContext)
	func executeSource(type: ExecuteType)
}

public protocol EditorManager: CodeEditor {
	var canSwitchToSourceMode: Bool { get }
	var canSwitchToPreviewMode: Bool { get }
	func switchTo(mode: EditorMode)
}

public extension EditorManager {
	// this was added later, so set a default for already implemented classes
	var canSwitchToPreviewMode: Bool { return false }
}
