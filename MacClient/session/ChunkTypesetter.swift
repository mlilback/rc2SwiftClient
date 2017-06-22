//
//  ChunkTypesetter.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let ChunkAttrName = NSAttributedStringKey("io.rc2.chunk")

@objc protocol ChunkTypsetterDelegate: class {
	func headerViewFor(chunk: DocumentChunk) -> NSView?
}

class ChunkTypesetter: NSATSTypesetter {
	weak var delegate: ChunkTypsetterDelegate?
	
	override func paragraphSpacing(beforeGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat
	{
		let defVal = super.paragraphSpacing(beforeGlyphAt: glyphIndex, withProposedLineFragmentRect: rect)
		guard let attrStr = attributedString, paragraphCharacterRange.length > 0 else { return defVal }
		if let _ = attrStr.attribute(ChunkAttrName, at: paragraphCharacterRange.location, effectiveRange: nil) as? DocumentChunk
		{
			return ChunkHeaderView.defaultHeight
		}
		return defVal
	}
}
