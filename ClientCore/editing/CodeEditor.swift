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

/// The current mode the editor is in
public enum EditorMode: Int {
	/// source editing
	case source = 0
	/// editing with a preview
	case preview
}

/// Methods necessary to edit code vai the DocumentManager
public protocol CodeEditor: class {
	var canExecute: Bool { get }
	func setContext(context: EditorContext)
	func executeSource(type: ExecuteType)
}

/// Methods for a class that can handle EditorMode changes
public protocol EditorManager: CodeEditor {
	var canSwitchToSourceMode: Bool { get }
	var canSwitchToPreviewMode: Bool { get }
	func switchTo(mode: EditorMode)
}

public extension EditorManager {
	// sets a default so only the preview implementation needs to implement
	var canSwitchToPreviewMode: Bool { return false }
}
