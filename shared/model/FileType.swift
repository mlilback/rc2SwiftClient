//
//  FileType.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#else
	import UIKit
#endif

public class FileType : Equatable {
	
	static var allFileTypes:[FileType] = {
		let fpath = NSBundle(forClass: Session.self).pathForResource("FileTypes", ofType: "plist")
		let dict = NSDictionary(contentsOfFile: fpath!)
		let rawTypes = dict!["FileTypes"] as! NSArray
		return rawTypes.map({ FileType(dictionary: $0 as! NSDictionary) })
	}()
	
	static var imageFileTypes:[FileType] = { allFileTypes.filter { return $0.isImage } }()
	static var textFileTypes:[FileType] = { allFileTypes.filter { return $0.isTextFile } }()
	static var importableFileTypes:[FileType] = { allFileTypes.filter { return $0.isImportable } }()
	static var creatableFileTypes:[FileType] = { allFileTypes.filter { return $0.isCreatable } }()
	
	var name:String { return typeDict["Name"] as! String }
	var fileExtension:String { return typeDict["Extension"] as! String }
	var details:String {return typeDict["Description"] as! String }
	var iconName:String? {return typeDict["IconName"] as? String }
	var mimeType:String {
		if let mtype = typeDict["MimeType"] as! String? {
			return mtype
		}
		return isTextFile ? "text/plain" : "application/octet-stream"
	}

	var isTextFile:Bool { return boolPropertyValue("IsTextFile") }
	var isImportable:Bool { return boolPropertyValue("Importable") }
	var isCreatable:Bool { return boolPropertyValue("Creatable") }
	var isImage:Bool { return boolPropertyValue("IsImage") }
	var isSourceFile:Bool { return boolPropertyValue("IsSrc") }
	var isSweave:Bool { return boolPropertyValue("IsSweave") }
	var isRMarkdown:Bool { return boolPropertyValue("IsRMarkdown") }
	var isExecutable:Bool { return boolPropertyValue("IsExecutable") }
	
	private let typeDict : NSDictionary
	
	static func fileTypeWithExtension(anExtension:String?) -> FileType? {
		guard let ext = anExtension else { return nil }
		let filtered:[FileType] = FileType.allFileTypes.filter {return $0.fileExtension == ext }
		return filtered.first
	}
	
	private func boolPropertyValue(key:String) -> Bool {
		if let nval = typeDict[key] as! NSNumber? {
			return nval.boolValue
		}
		return false
	}
	
	init(dictionary:NSDictionary) {
		typeDict = dictionary
	}

	///image function differs based on platform
#if os(OSX)
	func image() -> NSImage? {
		let imgName = "file-\(fileExtension)"
		if let img = NSImage(named: imgName) {
			img.backgroundColor = NSColor.clearColor()
			return img
		}
		return NSImage(named: "file-plain")
	}
	func fileImage() -> NSImage? {
		if let iname = self.iconName {
			var img:NSImage?
			img = NSImage(named: iname)
			if (img == nil) {
				img = NSWorkspace.sharedWorkspace().iconForFileType(self.fileExtension)
			}
			img?.size = NSMakeSize(48, 48)
			if (img != nil) {
				return img
			}
		}
		return image()
	}
#else
	func image() -> UIImage? {
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

public func ==(a: FileType, b: FileType) -> Bool {
	return a.fileExtension == b.fileExtension
}
