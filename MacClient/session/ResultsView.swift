//
//  ResultsView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class ResultsView : TextViewWithContextualMenu {
	override func awakeFromNib() {
		super.awakeFromNib()
		usesFindBar = true
	}
}
