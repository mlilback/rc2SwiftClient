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
	} }
	
	@objc dynamic var fileName: String?
}
