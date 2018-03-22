//
//  MarkdownViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SyntaxParsing

class MarkdownViewItem: NotebookViewItem {
	var dummyView: NSView!
	
	override func viewDidLoad() {
		dummyView = NSView(frame: .zero)
		middleView?.removeFromSuperview()
		middleView = nil
		resultTextView?.removeFromSuperview()
		resultTextView = nil
		super.viewDidLoad()
	}
	
	override var nibName: NSNib.Name? { return NSNib.Name(rawValue: "NotebookViewItem") }
	override var resultView: NSView { return dummyView }
	override var resultOuterView: NSView { return dummyView }
	
	override func prepareForReuse() {
		super.prepareForReuse()
		dummyView.frame = .zero
	}
}

