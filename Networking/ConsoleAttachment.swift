//
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

public enum ConsoleAttachmentType: Int {
	case image, file
}

public protocol ConsoleAttachment: JSONDecodable, JSONEncodable {
	func asAttributedString() -> NSAttributedString
}
