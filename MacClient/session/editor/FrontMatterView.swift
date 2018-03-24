//
//  FrontMatterView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class FrontMatterView: NSView {
	@IBOutlet private var sourceView: SourceTextView!
	@IBOutlet var topView: NSView?
	@IBOutlet var groupView: NSView?
	
	var frontMatterText: String {
		get { return sourceView.string }
		set { sourceView.replace(text: newValue) }
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		topView?.wantsLayer = true
//		wantsLayer = true
//		groupView?.wantsLayer = true
		groupView?.layer?.borderWidth = 1
		groupView?.layer?.borderColor = CGColor.black
		topView?.layer?.backgroundColor = noteBookFrontMatterColor.cgColor
	}
	
	@IBAction func addChunk(_ sender: Any?) {
		
	}
}

extension FrontMatterView: NSCollectionViewElement {
	
}
