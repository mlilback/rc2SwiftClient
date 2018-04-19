//
//  NotebookEntryView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class NotebookEntryView: NSView {
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var resultView: SourceTextView!
	var performLayout: (() -> Void)?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		// Some preferences:
		layer?.borderColor = notebookBorderColor.cgColor
		layer?.borderWidth = notebookItemBorderWidth
		// These are most appropriate for code text:
		sourceView.smartInsertDeleteEnabled = false
		sourceView.isAutomaticQuoteSubstitutionEnabled = false
		sourceView.isAutomaticSpellingCorrectionEnabled = false
	}
	
	override func layout() {
		super.layout()
		performLayout?()
	}
	
	override func resizeSubviews(withOldSize oldSize: NSSize) {
		// don't allow this
	}
}
