//
//  MacFileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let LastImportDirectoryKey = "rc2.LastImportDirectory"

class MacFileImporter: NSObject, NSOpenSavePanelDelegate {
	typealias AcceptDropHandler = ([NSURL], Bool) -> Void
	
	var pboardReadOptions:Dictionary<String,AnyObject> {
		return [NSPasteboardURLReadingFileURLsOnlyKey:true,
			NSPasteboardURLReadingContentsConformToTypesKey:[kUTTypePlainText, kUTTypePDF]];
	}

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
	
	func validateTableViewDrop(info:NSDraggingInfo) -> NSDragOperation {
		guard info.draggingSource() == nil else  { return NSDragOperation.None } //don't allow local drags
		let urls = info.draggingPasteboard().readObjectsForClasses([NSURL.self], options: pboardReadOptions)
		guard urls?.count > 0 else { return NSDragOperation.None } //must have a url
		let acceptableTypes = FileType.importableFileTypes.map() { $0.fileExtension }
		for aUrl in urls! {
			//if not a valid filetype extension, return .None
			if !acceptableTypes.contains(aUrl.pathExtension) { return NSDragOperation.None }
		}
		//must be good
		return NSDragOperation.Copy
	}
	
	func acceptTableViewDrop(info:NSDraggingInfo, workspace:Workspace, window:NSWindow, handler:AcceptDropHandler)
	{
		assert(validateTableViewDrop(info) != NSDragOperation.None, "validate wasn't called on drag info")
		let urls = info.draggingPasteboard().readObjectsForClasses([NSURL.self], options: pboardReadOptions) as? [NSURL]
		guard urls?.count > 0 else { return }
		let existingNames = workspace.files.map() { $0.name }
		if urls?.filter({ existingNames.contains($0.lastPathComponent!) }).first != nil {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Replace existing file(s)?", comment: "")
			alert.informativeText = NSLocalizedString("One or more files already exist with the same name as a dropped file", comment:"")
			alert.addButtonWithTitle(NSLocalizedString("Replace", comment:""))
			alert.addButtonWithTitle(NSLocalizedString("Cancel", comment:""))
			let uniqButton = alert.addButtonWithTitle(NSLocalizedString("Create Unique Names", comment:""))
			uniqButton.keyEquivalent = "u"
			//following is stupid conversion to bad swift conversion of property. field radar 24660685
			uniqButton.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
			alert.beginSheetModalForWindow(window) { response in
				guard response != NSAlertSecondButtonReturn else { return }
				handler(urls!, response == NSAlertFirstButtonReturn)
			}
		} else {
			handler(urls!, true)
		}
	}

	func uniqueFileName(desiredName:String, inWorkspace workspace:Workspace) -> String {
		var i = 1
		let nsname = NSString(string:desiredName)
		let baseName = nsname.stringByDeletingPathExtension
		let pathExtension = nsname.pathExtension
		var useableName = desiredName
		let existingNames = workspace.files.map() { return $0.name }
		while(true) {
			let newName = baseName + " \(i)." + pathExtension
			if !existingNames.contains(newName) {
				useableName = newName
				break;
			}
			i += 1
		}
		return useableName
	}
}
