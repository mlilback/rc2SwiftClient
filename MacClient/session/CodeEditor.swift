//
//  CodeEditor.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import ReactiveSwift
import SyntaxParsing
import Result
import SwiftyUserDefaults

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

protocol EditorContext: class {
	var currentDocument: MutableProperty<Document?> { get }
	var editorFont: MutableProperty<NSFont> { get }
	var parser: SyntaxParser? { get }
	var notificationCenter: NotificationCenter { get }
	func save(document: Document) -> SignalProducer<String, Rc2Error>
	func load(file: AppFile?) -> SignalProducer<String?, Rc2Error>
}


