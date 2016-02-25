//
//  DocumentChunk
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

enum ChunkType {
	case Documentation, RCode, Equation
}

enum EquationType: String {
	case NotAnEquation = "invalid", Inline = "inline", Display = "display", MathML = "MathML"
}

class DocumentChunk: NSObject {
	let chunkNumber:Int
	let name:String?
	let type:ChunkType
	
	var equationType:EquationType = .NotAnEquation
	var contentOffset:UInt = 0
	//should only be used by the parser/highlighter
	var parseRange:NSRange = NSRange(location: 0,length: 0)
	
	init(chunkType:ChunkType, chunkNumber:Int, name:String?=nil) {
		self.chunkNumber = chunkNumber
		self.type = chunkType
		self.name = name
		super.init()
	}
	
	convenience init(equationType:EquationType, chunkNumber:Int) {
		self.init(chunkType: .Equation, chunkNumber:chunkNumber)
		self.equationType = equationType
	}
	
	override var description: String {
		switch(self.type) {
			case .RCode:
				return "R chunk \(chunkNumber) \"\(name)\""
			case .Documentation:
				return "documentation chunk \(chunkNumber)"
			case .Equation:
				return "\(equationType.rawValue) equation chunk \(chunkNumber)"
		}
	}
}
