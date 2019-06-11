//
//  InlineEquationEditorController.swift
//
//  Copyright ©2018 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import SyntaxParsing
import iosMath

class InlineEquationEditorController: NSViewController {
	@IBOutlet private var equationView: MTMathUILabel!
	@IBOutlet private var editor: NSTextView!
	@IBOutlet private var cancelButton: NSButton!
	
	var chunk: InlineEquationChunk?
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
		assert(chunk != nil)
		equationView.latex = chunk!.rawText
		editor.textStorage?.replace(with: chunk!.rawText)
		if let editorFont = font {
			editor.font = editorFont
		}
	}
	
	override func viewWillDisappear() {
		super.viewWillDisappear()
		if !canceled {
			print("saving latex: \(editor.string)")
			chunk?.contents = NSAttributedString(string: editor.string)
			saveAction?(self, true)
		}
	}
}

extension InlineEquationEditorController: NSTextViewDelegate {
	func textDidChange(_ notification: Notification) {
		equationView.latex = editor.string
	}
}
