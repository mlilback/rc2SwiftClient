//
//  FileType.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
#if os(OSX)
	import AppKit
#else
	import UIKit
#endif

public class FileType: JSONDecodable {
	
	public static var allFileTypes: [FileType] = {
		guard let furl = Bundle(for: FileType.self).url(forResource: "FileTypes", withExtension: "json"),
			let data = try? Data(contentsOf: furl),
			let json = try? JSON(data: data)
			else {
				fatalError()
		}
		// swiftlint:disable:next force_try
		return try! json.decodedArray(at: "FileTypes", type: FileType.self)
	}()
	
	public static var imageFileTypes: [FileType] = { allFileTypes.filter { return $0.isImage } }()
	public static var textFileTypes: [FileType] = { allFileTypes.filter { return $0.isTextFile } }()
	public static var importableFileTypes: [FileType] = { allFileTypes.filter { return $0.isImportable } }()
	public static var creatableFileTypes: [FileType] = { allFileTypes.filter { return $0.isCreatable } }()
	
	public static func fileType(withExtension ext: String) -> FileType? {
		let filtered: [FileType] = FileType.allFileTypes.filter {return $0.fileExtension == ext }
		return filtered.first
	}

	public static func fileType(forFileName fileName: String) -> FileType? {
		guard let range = fileName.range(of: ".", options: .backwards) else {
			return nil
		}
		return fileType(withExtension: fileName.substring(from: range.upperBound))
	}
	
	public let name: String
	public let fileExtension: String
	public let uti: String
	public let details: String?
	public let iconName: String?
	private let rawMimeType: String?
	private let json: JSON
	
	public var mimeType: String {
		if rawMimeType != nil { return rawMimeType! }
		return (isTextFile ? "text/plain": "application/octet-string") as String
	}
	
	public required init(json: JSON) throws {
		self.json = json
		name = try json.getString(at: "Name")
		fileExtension = try json.getString(at: "Extension")
		uti = try json.getString(at: "UTTypeIdentifier")
		details = json.getOptionalString(at: "Description")
		iconName = json.getOptionalString(at: "IconName")
		rawMimeType = json.getOptionalString(at: "MimeType")
	}
	
	/// Is the user allowed to upload files of this type
	public var isImportable: Bool { return boolPropertyValue("Importable") }
	// can the user create a new file of this type in the editor
	public var isCreatable: Bool { return boolPropertyValue("Creatable") }
	/// is this a file we can tell the server to execute
	public var isExecutable: Bool { return boolPropertyValue("Executable") }
	/// is this a source file that can be edited
	public var isSourceFile: Bool { return boolPropertyValue("IsSrc") }
	public var isTextFile: Bool { return boolPropertyValue("IsTextFile") }
	public var isImage: Bool { return boolPropertyValue("IsImage") }
	public var isSweave: Bool { return boolPropertyValue("IsSweave") }
	public var isRMarkdown: Bool { return boolPropertyValue("IsRMarkdown") }
	
	fileprivate func boolPropertyValue(_ key: String) -> Bool {
		guard let prop = try? json.getBool(at: key) else { return false }
		return prop
	}
}

extension FileType {
	///image function differs based on platform
	#if os(OSX)
	public func image() -> NSImage? {
		let imgName = "file-\(fileExtension)"
		if let img = NSImage(named: imgName) {
			img.backgroundColor = NSColor.clear
			return img
		}
		return NSImage(named: "file-plain")
	}
	func fileImage() -> NSImage? {
		if let iname = self.iconName {
			var img: NSImage?
			img = NSImage(named: iname)
			if img == nil {
				img = NSWorkspace.shared().icon(forFileType: self.fileExtension)
			}
			img?.size = NSSize(width: 48, height: 48)
			if img != nil {
				return img
			}
		}
		return image()
	}
	#else
	public func image() -> UIImage? {
		if let img = UIImage(named: "console/\(self.fileExtension)-file") {
			return img
		}
		return UIImage(named:"console/plain-file")
	}
	func fileImage() -> UIImage? {
		return image()
	}
	#endif
}

extension FileType: Equatable {
	static public func == (a: FileType, b: FileType) -> Bool {
		return a.fileExtension == b.fileExtension
	}
}
