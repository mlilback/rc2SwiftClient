//
//  MonoFontManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import CoreText

//supplies list of installed monspaced fonts
open class MonoFontManager {
	var mappings = [String: String]()
	
	init() {
		loadFontInfo()
	}
	
	func fontDisplayNames() -> [String] { return mappings.values.sorted() }
	func fontNames() -> [String] { return mappings.keys.sorted() }
	func displayNameForFont(_ fontName: String) -> String? {
		return mappings[fontName]
	}
	
	func loadFontInfo() {
		mappings.removeAll()
		let traits: [String:AnyObject] = [kCTFontSymbolicTrait as String: Int(CTFontSymbolicTraits.monoSpaceTrait.rawValue) as AnyObject]
		let attrs: [String:AnyObject] = [kCTFontTraitsAttribute as String: traits as AnyObject, kCTFontStyleNameAttribute as String: "Regular" as AnyObject]
		// swiftlint:disable force_cast
		let fdesc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
		let descs = CTFontDescriptorCreateMatchingFontDescriptors(fdesc, nil)! as [AnyObject]
		for anObj in descs {
			let aDesc = anObj as! CTFontDescriptor
			let fname = CTFontDescriptorCopyAttribute(aDesc, kCTFontFamilyNameAttribute)! as! String
			let face = CTFontDescriptorCopyAttribute(aDesc, kCTFontStyleNameAttribute) as! String
			let pname = CTFontDescriptorCopyAttribute(aDesc, kCTFontNameAttribute) as! String!
			let traitDict = (CTFontDescriptorCopyAttribute(aDesc, kCTFontTraitsAttribute) as! NSDictionary) as! [String:AnyObject]
			let traits = traitDict[kCTFontSymbolicTrait as String] as! Int
			//exclude symbol and script fonts and any non Regular fonts (which should have been exclulded above, but all styles of SourceCodePro were being returned)
			if (traits >> 28) <= 8 && face == "Regular" {
				if mappings[pname!] == nil {
					mappings[pname!] = fname
				}
			}
		}
		// swiftlint:enable force_cast
	}
}
