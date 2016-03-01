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
	var contentOffset:Int = 0
	//should only be used by the parser/highlighter
	var parsedRange:NSRange = NSRange(location: 0,length: 0)
	
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
	
	func duplicateWithChunkNumber(newNum:Int) -> DocumentChunk {
		let dup = DocumentChunk(chunkType: type, chunkNumber: newNum, name: name)
		dup.parsedRange = parsedRange
		dup.contentOffset = contentOffset
		dup.equationType = equationType
		return dup
	}
	
	override func isEqual(object: AnyObject?) -> Bool {
		if let other = object as? DocumentChunk {
			return other.chunkNumber == chunkNumber && other.type == type && other.name == name && NSEqualRanges(parsedRange, other.parsedRange)
		}
		return false
	}
	
	override var hash:Int {
		return chunkNumber.hashValue + type.hashValue + (name == nil ? 0 : name!.hashValue)
	}
	
	override var description: String {
		let range = NSStringFromRange(parsedRange)
		switch(self.type) {
			case .RCode:
				return "R chunk \(chunkNumber) \"\((name == nil ? "" : name!))\" (\(range))"
			case .Documentation:
				return "documentation chunk \(chunkNumber) (\(range))"
			case .Equation:
				return "\(equationType.rawValue) equation chunk \(chunkNumber) (\(range))"
		}
	}
}
