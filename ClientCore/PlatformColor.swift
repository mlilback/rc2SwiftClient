//
//  PlatformColor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

#if os(OSX)
	import AppKit
	public typealias PlatformColor = NSColor
	public typealias PlatformImage = NSImage
#else
	import UIKit
	public typealias PlatformColor = UIColor
	public typealias PlatformImage = UIImage
#endif

extension CharacterSet {
	/// valid characters in a hexadecimal string, including both upper- and lowercase
	static var hexadecimal: CharacterSet = { CharacterSet(charactersIn: "0123456789AaBbCcDdEeFf") }()
}

public extension PlatformColor {
	/// initialize a color from a hex string
	///
	/// - Parameters:
	///   - hexString: A six character hex string in RRGGBB format, with an optional # at the start
	///   - alpha: the alpha value to use, 0…1.0, defaults to 1.0
	public convenience init?(hexString: String, alpha: CGFloat = 1.0) {
		var hcode = hexString
		if hcode.hasPrefix("#") {
			hcode = String(hcode[hcode.index(hcode.startIndex, offsetBy: 1)...])
		}
		guard hcode.count == 6, hcode.trimmingCharacters(in: CharacterSet.hexadecimal) == "" else { return nil }

		let redHex = String(hexString[..<hexString.index(hexString.startIndex, offsetBy: 2)])
		let greenHex = String(hexString[hexString.index(hexString.startIndex, offsetBy: 2) ..< hexString.index(hexString.startIndex, offsetBy: 4)])
		let blueHex = String(hexString[hexString.index(hexString.startIndex, offsetBy: 4) ..< hexString.index(hexString.startIndex, offsetBy: 6)])
		var redInt: CUnsignedInt = 0
		var greenInt: CUnsignedInt = 0
		var blueInt: CUnsignedInt = 0
		Scanner(string: redHex).scanHexInt32(&redInt)
		Scanner(string: greenHex).scanHexInt32(&greenInt)
		Scanner(string: blueHex).scanHexInt32(&blueInt)
		let divisor: CGFloat = 255.0

		self.init(red: CGFloat(redInt) / divisor, green: CGFloat(greenInt) / divisor, blue: CGFloat(blueInt) / divisor, alpha: alpha)
	}

	/// the color as a hex string, without a leading # character
	public var hexString: String {
		let red = UInt8(redComponent * 255.0)
		let green = UInt8(greenComponent * 255.0)
		let blue = UInt8(blueComponent * 255.0)
		return String(format: "%0.2x%0.2x%0.2x", red, green, blue)
	}
}
