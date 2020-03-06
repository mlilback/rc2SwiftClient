//
//  SourceEditorController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class SourceEditorController: BaseSourceEditorController
{
	override var isRDocument: Bool { return context?.currentDocument.value?.isRDocument ?? false }
	
	override func contentsChanged(_ contents: NSTextStorage, range: NSRange, changeLength delta: Int) {
//		guard let psr = parser else { return }
//		psr.contentsChanged(range: range, changeLength: delta)
		colorizeHighlightAttributes()
	}
}
