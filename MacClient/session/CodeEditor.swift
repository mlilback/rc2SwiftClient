//
//  CodeEditor.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking

enum EditorMode: Int {
	case notebook = 0
	case source
}

protocol CodeEditor: class, Searchable {
	var canExecute: Bool { get }
	var documentLoaded: Bool { get }
	func executeSource(type: ExecuteType)
	func save(state: inout SessionState.EditorState)
	func restore(state: SessionState.EditorState)
	func fileChanged(file: AppFile?)
}

protocol EditorManager: CodeEditor {
	var canSwitchToNotebookMode: Bool { get }
	var canSwitchToSourceMode: Bool { get }
	func switchTo(mode: EditorMode)
}
