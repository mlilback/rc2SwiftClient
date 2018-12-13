//
//  SourceEditorLayoutManager.swift
//  MacClient
//
//  Created by Mark Lilback on 11/8/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa

class SourceEditorLayoutManager: NSLayoutManager {
	override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
		if rectCount > 1 {
			let firstSize = rectArray.pointee.size
			let ourData = UnsafeMutablePointer<NSRect>(mutating: rectArray).advanced(by: rectCount - 1)
			ourData.pointee.size = CGSize(width: firstSize.width, height: ourData.pointee.size.height)
		}
		super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
	}
}
