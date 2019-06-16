//
//  LivePreviewEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/30/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import Down
import MJLLogger
import ClientCore
import WebKit

class LivePreviewEditorController: BaseSourceEditorController {
	var outputController: LivePreviewOutputController? { didSet { outputControllerChanged() } }
	
	private var webView: WKWebView?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		editor?.isEditable = true
	}

	override func setContext(context: EditorContext) {
		super.setContext(context: context)
	}
	
	func outputControllerChanged() {
		outputController?.editorContext = self.context
		// need to update with current generated contents
	}
	
//	override func loaded(content: String) {
//		do {
//			let rendered = try content.toHTML([.normalize, .safe, .sourcePos])
//			editor?.string = rendered
//		} catch {
//			Log.warn("preview editor failed to parse markdown")
//		}
//	}
	
	/// subclasses should override and save contents via save(edits:). super should not be called
	override func editsNeedSaving() {
		
	}
}
