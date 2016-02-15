//
//  MacFileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let LastImportDirectoryKey = "rc2.LastImportDirectory"

class MacFileImporter: NSObject, NSOpenSavePanelDelegate {
	
	func performFileImport(window:NSWindow, completionHandler:(Bool) -> Void) {
		
		let panel = NSOpenPanel()
		if let bmarkData = NSUserDefaults.standardUserDefaults().objectForKey(LastImportDirectoryKey) as? NSData {
			do {
				panel.directoryURL = try NSURL(byResolvingBookmarkData: bmarkData, options: [], relativeToURL: nil, bookmarkDataIsStale: nil)
			} catch {
			}
		}
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.resolvesAliases = true
		panel.allowsMultipleSelection = true
		panel.prompt = NSLocalizedString("Import", comment:"")
		panel.message = NSLocalizedString("Select Files to Import", comment:"")
		panel.delegate = self
		panel.treatsFilePackagesAsDirectories = true
		panel.allowedFileTypes = FileType.importableFileTypes.map { $0.fileExtension }
		
		panel.beginSheetModalForWindow(window) { result in
			do {
				let bmark = try panel.directoryURL?.bookmarkDataWithOptions([], includingResourceValuesForKeys: nil, relativeToURL: nil)
				NSUserDefaults.standardUserDefaults().setObject(bmark, forKey: LastImportDirectoryKey)
			} catch let err {
				log.error("why did we get error creating import bookmark: \(err)")
			}
			completionHandler(result == NSFileHandlingPanelOKButton)
		}
	}
}
