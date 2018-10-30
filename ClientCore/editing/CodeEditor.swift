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
	case notebook = 0
	case source
	case preview
}

public protocol CodeEditor: class {
	var canExecute: Bool { get }
	func setContext(context: EditorContext)
	func executeSource(type: ExecuteType)
}

public protocol EditorManager: CodeEditor {
	var canSwitchToNotebookMode: Bool { get }
	var canSwitchToSourceMode: Bool { get }
	var canSwitchToPreviewMode: Bool { get }
	func switchTo(mode: EditorMode)
}

public extension EditorManager {
	// this was added later, so set a default for already implemented classes
	var canSwitchToPreviewMode: Bool { return false }
}
