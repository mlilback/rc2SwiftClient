 //
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class MacConsoleAttachment: NSObject, ConsoleAttachment {
	private let type: ConsoleAttachmentType
	private let image: SessionImage?
	private let fileId:Int32
	private let fileVersion:Int32
	private let fileName:String?
	private let fileExtension:String?
	
	public static func supportsSecureCoding() -> Bool {
		return true
	}

	public init(file inFile:File) {
		type = .File
		image = nil
		fileId = Int32(inFile.fileId)
		fileVersion = Int32(inFile.version)
		fileName = inFile.name
		fileExtension = inFile.fileType.fileExtension
		super.init()
	}
	
	public init(image inImage:SessionImage) {
		type = .Image
		image = inImage
		fileName = nil
		fileExtension = nil
		fileId = 0
		fileVersion = 0
		super.init()
	}

	public required init?(coder decoder:NSCoder) {
		self.type = ConsoleAttachmentType(rawValue: Int(decoder.decodeIntForKey("type")))!
		self.image = decoder.decodeObjectForKey("image") as? SessionImage
		self.fileId = decoder.decodeIntForKey("fileId")
		self.fileVersion = decoder.decodeIntForKey("fileVersion")
		self.fileName = decoder.decodeObjectForKey("fileName") as? String
		self.fileExtension = decoder.decodeObjectForKey("fileExtension") as? String
	}
	
	public func encodeWithCoder(coder: NSCoder) {
		coder.encodeInt(Int32(type.rawValue), forKey: "type")
		coder.encodeObject(image, forKey: "image")
		coder.encodeInt(fileId, forKey: "fileId")
		coder.encodeInt(fileVersion, forKey: "fileVersion")
		coder.encodeObject(fileName, forKey: "fileName")
		coder.encodeObject(fileExtension, forKey: "fileExtension")
	}
	
	private func fileAttachmentData() -> (NSFileWrapper, NSImage?) {
		let data = NSKeyedArchiver.archivedDataWithRootObject(self)
		let file = NSFileWrapper(regularFileWithContents: data)
		file.filename = fileName
		file.preferredFilename = fileName
		return (file, FileType.fileTypeWithExtension(fileExtension)?.image())
	}
	
	private func imageAttachmentData() -> (NSFileWrapper, NSImage?) {
		let data = NSKeyedArchiver.archivedDataWithRootObject(self)
		let file = NSFileWrapper(regularFileWithContents: data)
		file.filename = image?.name
		file.preferredFilename = image?.name
		return (file, NSImage(named:"graph")!)
	}
	
	public func serializeToAttributedString() -> NSAttributedString {
		var file:NSFileWrapper?
		var image:NSImage?
		switch(type) {
			case .File:
				(file!, image) = fileAttachmentData()
			case .Image:
				(file!, image) = imageAttachmentData()
		}
		let attachment = NSTextAttachment(fileWrapper: file)
		let cell = NSTextAttachmentCell(imageCell: image)
		cell.image?.size = NSMakeSize(48, 48)
		attachment.attachmentCell = cell
		let str = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
		str.addAttribute(NSToolTipAttributeName, value: (attachment.fileWrapper?.filename)!, range: NSMakeRange(0,1))
		return str
	}
}

