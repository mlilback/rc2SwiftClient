//
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import Freddy
import Networking
import os

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
	
	public init(file inFile: AppFile) {
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
		image = try json.decode(at: "image", alongPath: .missingKeyBecomesNil, type: SessionImage.self)
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
	
	fileprivate func attachmentData(name: String, image: NSImage?) -> (FileWrapper, NSImage?)? {
		guard let data = try? toJSON().serialize() else {
			os_log("invalid json data in file attachment", log: .app)
			return nil
		}
		let file = FileWrapper(regularFileWithContents: data)
		file.filename = name
		file.preferredFilename = name
		return (file, image)
	}
	
	fileprivate func fileAttachmentData() -> (FileWrapper, NSImage?)? {
		return attachmentData(name: fileName ?? "untitled", image: FileType.fileType(withExtension: fileExtension!)?.image())
	}
	
	fileprivate func imageAttachmentData() -> (FileWrapper, NSImage?)? {
		return attachmentData(name: image?.name ?? "unnamed", image: #imageLiteral(resourceName: "graph"))
	}
	
	public func asAttributedString() -> NSAttributedString {
		var results: (FileWrapper, NSImage?)?
		switch type {
			case .file:
				results = fileAttachmentData()
			case .image:
				results = imageAttachmentData()
		}
		assert(results?.0 != nil)
		let attachment = NSTextAttachment(fileWrapper: results!.0)
		let cell = NSTextAttachmentCell(imageCell: results!.1)
		cell.image?.size = NSSize(width: 48, height: 48)
		attachment.attachmentCell = cell
		let str = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
		str.addAttribute(.toolTip, value: (attachment.fileWrapper?.filename)!, range: NSRange(location: 0, length: 1))
		return str
	}
}
