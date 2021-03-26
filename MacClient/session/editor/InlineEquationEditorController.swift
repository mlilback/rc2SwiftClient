//
//  InlineEquationEditorController.swift
//
//  Copyright ©2018 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import iosMath

class InlineEquationEditorController: NSViewController {
	@IBOutlet private var equationView: MTMathUILabel!
	@IBOutlet private var editor: NSTextView!
	@IBOutlet private var cancelButton: NSButton!

	var document: RmdDocument?
	var chunk: RmdDocumentChunk?
	var font: NSFont?

	var saveAction: ((InlineEquationEditorController, Bool) -> Void)?

	private var canceled = false

	@IBAction func cancelEdit(_ sender: Any?) {
		canceled = true
		saveAction?(self, false)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		equationView.labelMode = .text
		equationView.textAlignment = .center
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		precondition(chunk != nil)
		guard let content = document?.string(for: chunk!, type: .inner)
			else { fatalError("equation editor loaded without document") }
		equationView.latex = content
		editor.textStorage?.replace(with: content)
		if let editorFont = font {
			editor.font = editorFont
		}
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		if !canceled {
			saveAction?(self, true)
		}
	}
}

extension InlineEquationEditorController: NSTextViewDelegate {
	func textDidChange(_ notification: Notification) {
		equationView.latex = editor.string
	}
}
