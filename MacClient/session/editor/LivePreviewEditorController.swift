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

class LivePreviewEditorController: BaseSourceEditorController {
	
	override func viewDidLoad() {
		super.viewDidLoad()
		editor?.isEditable = true
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
