//
//  NotebookEditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking

class NotebookEditorController: AbstractSessionViewController, CodeEditor {
	@objc dynamic var canExecute: Bool { return true }
	
	func executeSource(type: ExecuteType) {
		
	}
	
	func save(state: inout SessionState.EditorState) {
		
	}
	
	func restore(state: SessionState.EditorState) {
		
	}
	
	func fileChanged(file: AppFile?) {
		
	}
	
	
}
