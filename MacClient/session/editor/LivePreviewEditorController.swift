//
//  LivePreviewEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/30/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import MJLLogger
import ClientCore
import WebKit
import ReactiveSwift
import Rc2Common
import SwiftyUserDefaults

class LivePreviewEditorController: BaseSourceEditorController {
	var outputController: LivePreviewOutputController? { didSet {
		outputController?.parserContext = parser
		outputController?.saveProducer = { [weak self] () -> SignalProducer<(), Rc2Error> in
			guard let me = self else { fatalError() }
			return me.saveWithProgress()
				.map { _ in () }
		}
	} }

	private var webView: WKWebView?
	private var inlinePopover: NSPopover?

	// used to prevent recursion (due to didSet) in outputControllerChanged()
	private var inOutputChange = false

	// used to wrap lastChange with a queue, but that was causing recursive errors. Instead, this values should only be used on the main thread
	var textMonitor: TextChangeMonitor?

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(showEquationEditor(_:)) {
			return currentInlineChunk()?.isEquation ?? false
		}
		return super.validateMenuItem(menuItem)
	}
	
	override func viewDidLoad() {
		useParser = true
		super.viewDidLoad()
		editor?.isEditable = true
		textMonitor = TextChangeMonitor(delegate: self)
		
		contextualMenuAdditions = NSMenu(title: "preview")
		let item = NSMenuItem(title: "Equation Editor…", action: #selector(showEquationEditor(_:)), keyEquivalent: "")
		contextualMenuAdditions?.addItem(item)
	}

	@IBAction @objc func showEquationEditor(_ sender: Any) {
		guard let doc = parser?.parsedDocument.value,
			  let chunk = currentInlineChunk(),
			  let editor = editor
		else { return }
		let editorVC = InlineEquationEditorController()
		editorVC.document = doc
		editorVC.chunk = chunk
		editorVC.font = context!.editorFont.value
		editorVC.saveAction = { (editor, save) in
			self.inlinePopover?.close()
			// TODO: handle save
		}
		var range = editor.selectedRange()
		if range.length < 1 {
			range.length = 1
		}
		let winRect = view.window!.convertFromScreen(editor.firstRect(forCharacterRange: range, actualRange: nil))
		let editorRect = editor.convert(winRect, from: nil)
		if inlinePopover == nil {
			inlinePopover = NSPopover()
			inlinePopover?.behavior = .semitransient
		}
		inlinePopover?.contentViewController = editorVC
		inlinePopover?.show(relativeTo: editorRect, of: editor, preferredEdge: .maxX)
	}
	
	/// Gets the inline chunk that the cursor is inside of
	/// - Returns: The linline chunk or nil if cursor not inside an inline chunk
	private func currentInlineChunk() -> RmdDocumentChunk? {
		guard let range = editor?.selectedRange(),
			  range.location != NSNotFound,
			  range.location < editor!.string.count,
			  let chunks = parser?.parsedDocument.value?.chunks(in: range),
			  chunks.count == 1,
			  chunks[0].children.count > 0,
			  let ichunk = chunks[0].childContaining(location: range.location)
		else { return nil }
		return ichunk
	}
	
	override func setContext(context: EditorContext) {
		super.setContext(context: context)
		precondition(outputController != nil)
		outputController?.setEditorContext(context)
	}

	override func loaded(content: String) {
		guard context?.currentDocument.value?.isRmarkdown ?? false else {
			super.loaded(content: "")
			return
		}
		super.loaded(content: content)
		colorizeHighlightAttributes()
	}

	override func contentsChanged(_ contents: NSTextStorage, range: NSRange, changeLength delta: Int) {
		// really does nothing, but call to be safe
		super.contentsChanged(contents, range: range, changeLength: delta)
		textMonitor?.textChanged(range: range, delta: delta)
	}

	/// subclasses should override and save contents via save(edits:). super should not be called
	override func editsNeedSaving() {

	}

	func textDidBeginEditing(_ notification: Notification) {
		textMonitor?.didBeginEditing()
	}

	func textDidEndEditing(_ notification: Notification) {
		textMonitor?.didEndEditing()
	}
}

extension LivePreviewEditorController: TextChangeMonitorDelegate {
	func contentsEdited(_ monitor: TextChangeMonitor, range: NSRange)  {
		if let oc = outputController,
		   oc.contentsEdited(contents: editor!.string, range: range, delta: 0)
		{
			if ignoreContentChanges { return }
			save(edits: editor!.string, reload: false)
		}
	}
	
}
