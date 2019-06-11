//
//  SourceTextView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

// Override NSText/View methods so that changes will update our views.
public class SourceTextView: NSTextView {
	@objc public var changeCallback: (() -> Void)?
	
	public override func awakeFromNib() {
		super.awakeFromNib()
		postsBoundsChangedNotifications = true
	}
	
	public override func insertNewline(_ sender: Any?) {
		super.insertNewline(sender)
		changeCallback?()
	}
	
	public override func deleteForward(_ sender: Any?) {
		super.deleteForward(sender)
		changeCallback?()
	}
	
	public override func deleteBackward(_ sender: Any?) {
		super.deleteBackward(sender)
		changeCallback?()
	}
	
	public override func paste(_ sender: Any?) {
		super.paste(sender)
		changeCallback?()
	}
}
