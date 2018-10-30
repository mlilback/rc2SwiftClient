//
//  LivePreviewController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/29/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa

class LivePreviewController: AbstractSessionViewController, OutputController {
	var contextualMenuDelegate: ContextualMenuDelegate?
	
	@IBOutlet weak var outputView: NSTextView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		outputView.string = "Some text here\nJust to see\n"
	}
}
