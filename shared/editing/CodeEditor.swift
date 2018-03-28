//
//  EditorContext.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import ReactiveSwift
import SyntaxParsing

enum EditorMode: Int {
	case notebook = 0
	case source
}

protocol CodeEditor: class, Searchable {
	var canExecute: Bool { get }
	func setContext(context: EditorContext)
	func executeSource(type: ExecuteType)
}

protocol EditorManager: CodeEditor {
	var canSwitchToNotebookMode: Bool { get }
	var canSwitchToSourceMode: Bool { get }
	func switchTo(mode: EditorMode)
}
