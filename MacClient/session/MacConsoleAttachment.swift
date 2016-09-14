 //
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

open class MacConsoleAttachment: NSObject, ConsoleAttachment {
	open let type: ConsoleAttachmentType
	let image: SessionImage?
	let fileId:Int32
	let fileVersion:Int32
	let fileName:String?
	let fileExtension:String?
	
	public static var supportsSecureCoding : Bool {
		return true
	}

	public init(file inFile:File) {
		type = .file
		image = nil
		fileId = Int32(inFile.fileId)
		fileVersion = Int32(inFile.version)
		fileName = inFile.name
		fileExtension = inFile.fileType.fileExtension
		super.init()
	}
	
	public init(image inImage:SessionImage) {
		type = .image
		image = inImage
		fileName = nil
		fileExtension = nil
		fileId = 0
		fileVersion = 0
		super.init()
	}

	public required init?(coder decoder:NSCoder) {
		self.type = ConsoleAttachmentType(rawValue: Int(decoder.decodeCInt(forKey: "type")))!
		self.image = decoder.decodeObject(forKey: "image") as? SessionImage
		self.fileId = decoder.decodeCInt(forKey: "fileId")
		self.fileVersion = decoder.decodeCInt(forKey: "fileVersion")
		self.fileName = decoder.decodeObject(forKey: "fileName") as? String
		self.fileExtension = decoder.decodeObject(forKey: "fileExtension") as? String
	}
	
	open func encode(with coder: NSCoder) {
		coder.encodeCInt(Int32(type.rawValue), forKey: "type")
		coder.encode(image, forKey: "image")
		coder.encodeCInt(fileId, forKey: "fileId")
		coder.encodeCInt(fileVersion, forKey: "fileVersion")
		coder.encode(fileName, forKey: "fileName")
		coder.encode(fileExtension, forKey: "fileExtension")
	}
	
	fileprivate func fileAttachmentData() -> (FileWrapper, NSImage?) {
		let data = NSKeyedArchiver.archivedData(withRootObject: self)
		let file = FileWrapper(regularFileWithContents: data)
		file.filename = fileName
		file.preferredFilename = fileName
		return (file, FileType.fileTypeWithExtension(fileExtension)?.image())
	}
	
	fileprivate func imageAttachmentData() -> (FileWrapper, NSImage?) {
		let data = NSKeyedArchiver.archivedData(withRootObject: self)
		let file = FileWrapper(regularFileWithContents: data)
		file.filename = image?.name
		file.preferredFilename = image?.name
		return (file, NSImage(named:"graph")!)
	}
	
	open func serializeToAttributedString() -> NSAttributedString {
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

