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

	// used to prevent recursion (due to didSet) in outputControllerChanged()
	private var inOutputChange = false

	// used to wrap lastChange with a queue, but that was causing recursive errors. Instead, this values should only be used on the main thread
	var textMonitor: TextChangeMonitor?

	override func viewDidLoad() {
		useParser = true
		super.viewDidLoad()
		editor?.isEditable = true
		textMonitor = TextChangeMonitor(delegate: self)
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
