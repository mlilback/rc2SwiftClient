//
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public enum ConsoleAttachmentType: Int, Codable {
	case image, file
}

public protocol ConsoleAttachment: Codable {
	func asAttributedString() -> NSAttributedString
}
