//
//  LivePreviewEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/30/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa

class LivePreviewEditorController: AbstractEditorController {
	@IBOutlet weak var textEditor: SessionEditor!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		textEditor.isEditable = true
	}

	override func loaded(content: String) {
		
	}
	
	/// subclasses should override and save contents via save(edits:). super should not be called
	override func editsNeedSaving() {
		
	}
}
