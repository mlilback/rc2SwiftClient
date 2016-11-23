 //
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import Networking

public final class MacConsoleAttachment: ConsoleAttachment {
	let type: ConsoleAttachmentType
	let image: SessionImage?
	let fileId: Int
	let fileVersion: Int
	let fileName: String?
	let fileExtension: String?
	
	public class func from(data: Data) throws -> MacConsoleAttachment {
		let json = try JSON(data: data)
		return try MacConsoleAttachment(json: json)
	}
	
	public init(file inFile: File) {
		type = .file
		image = nil
		fileId = inFile.fileId
		fileVersion = inFile.version
		fileName = inFile.name
		fileExtension = inFile.fileType.fileExtension
	}
	
	public init(image inImage: SessionImage) {
		type = .image
		image = inImage
		fileName = nil
		fileExtension = nil
		fileId = 0
		fileVersion = 0
	}

	public init(json: JSON) throws {
		type = ConsoleAttachmentType(rawValue: try json.getInt(at: "type"))!
		image = try json.decode(at: "image", alongPath: .MissingKeyBecomesNil, type: SessionImage.self)
		fileId = try json.getInt(at: "fileId")
		fileVersion = try json.getInt(at: "fileVersion")
		fileName = json.getOptionalString(at: "fileName")
		fileExtension = json.getOptionalString(at: "fileExtension")
		if type == .file && fileExtension == nil && nil == FileType.fileType(withExtension: fileExtension!) {
			throw Rc2Error(type: .invalidJson, explanation: "file attachment had invalid file extension")
		}
	}

	public func toJSON() -> JSON {
		var props: [String: JSON] = [
			"type": .int(type.rawValue),
			"fileId": .int(fileId),
			"fileVersion": .int(fileVersion)
		]
		switch type {
		case .image:
			props["image"] = image!.toJSON()
		case .file:
			props["fileName"] = .string(fileName!)
			props["fileExtension"] = .string(fileExtension!)
		}
		return .dictionary(props)
	}
	
	fileprivate func fileAttachmentData() -> (FileWrapper, NSImage?) {
		let data = try! toJSON().serialize()
		let file = FileWrapper(regularFileWithContents: data)
		file.filename = fileName
		file.preferredFilename = fileName
		return (file, FileType.fileType(withExtension: fileExtension!)?.image())
	}
	
	fileprivate func imageAttachmentData() -> (FileWrapper, NSImage?) {
		let data = try! toJSON().serialize()
		let file = FileWrapper(regularFileWithContents: data)
		file.filename = image?.name
		file.preferredFilename = image?.name
		return (file, NSImage(named:"graph")!)
	}
	
	public func asAttributedString() -> NSAttributedString {
		var results:(FileWrapper, NSImage?)?
		switch(type) {
			case .file:
				results = fileAttachmentData()
			case .image:
				results = imageAttachmentData()
		}
		assert(results?.0 != nil)
		let attachment = NSTextAttachment(fileWrapper: results!.0)
		let cell = NSTextAttachmentCell(imageCell: results!.1)
		cell.image?.size = NSMakeSize(48, 48)
		attachment.attachmentCell = cell
		let str = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
		str.addAttribute(NSToolTipAttributeName, value: (attachment.fileWrapper?.filename)!, range: NSMakeRange(0,1))
		return str
	}
}

