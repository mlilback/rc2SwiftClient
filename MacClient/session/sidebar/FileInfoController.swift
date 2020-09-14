//
//  FileInfoController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Networking

class FileInfoController: NSViewController {
	var file: AppFile? { didSet {
		fileName = file?.name
		fileSize = NSNumber(value: file?.fileSize ?? 0)
		dateCreated = file?.dateCreated
		lastModified = file?.lastModified
		fileIcon = #imageLiteral(resourceName: "file-plain")
		if let iconName = file?.fileType.iconName, let icon = NSImage(named: NSImage.Name(iconName)) {
			fileIcon = icon
		} else {
			fileIcon = NSWorkspace.shared.icon(forFileType: file!.fileType.fileExtension)
			fileIcon?.size = NSSize(width: 48, height: 48)
		}
	} }

	@objc dynamic var fileName: String?
	@objc dynamic var fileSize: NSNumber?
	@objc dynamic var dateCreated: Date?
	@objc dynamic var lastModified: Date?
	@objc dynamic var fileIcon: NSImage?
}
