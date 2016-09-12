//
//  MacFileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


let LastImportDirectoryKey = "rc2.LastImportDirectory"
let ReplaceFilesKey = "rc2.ImportReplacesExistingFiles"

/** Handles importing via a save panel or drag and drop. */
class MacFileImportSetup: NSObject, NSOpenSavePanelDelegate {
	
	var pboardReadOptions:Dictionary<String,Any> {
		return [NSPasteboardURLReadingFileURLsOnlyKey:true as AnyObject,
			NSPasteboardURLReadingContentsConformToTypesKey:[kUTTypePlainText, kUTTypePDF]];
	}
	
	/** Prompts the user to select files to upload. 
		parameter window: the parent window to display the sheet on
		parameter workspace: the workspace the files will be imported into
		parameter completionHandler: a closure called with an array of files to import, or nil if the user canceled the import
	*/
	func performFileImport(_ window:NSWindow, workspace:Workspace, completionHandler:@escaping ([FileToImport]?) -> Void) {
		
		let defaults = UserDefaults.standard
		let panel = NSOpenPanel()
		if let bmarkData = defaults.object(forKey: LastImportDirectoryKey) as? Data {
			do {
				panel.directoryURL = try (NSURL(resolvingBookmarkData: bmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: nil) as URL)
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
		let accessoryView = NSButton(frame: NSZeroRect)
		accessoryView.setButtonType(.switch)
		accessoryView.title = NSLocalizedString("Replace existing files", comment: "")
		let replace = defaults.bool(forKey: ReplaceFilesKey)
		accessoryView.state = replace ? NSOffState : NSOnState
		panel.beginSheetModal(for: window) { result in
			do {
				let bmark = try (panel.directoryURL as NSURL?)?.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
				defaults.set(bmark, forKey: LastImportDirectoryKey)
				defaults.set(accessoryView.state == NSOnState, forKey: ReplaceFilesKey)
			} catch let err as NSError {
				os_log("why did we get error creating import bookmark: %@", err)
			}
			panel.close()
			if result == NSFileHandlingPanelOKButton && panel.urls.count > 0 {
				let replaceFiles = accessoryView.state == NSOnState
				let files = panel.urls.map() { url in
					FileToImport(url: url, uniqueName: replaceFiles ? self.uniqueFileName(url.lastPathComponent, inWorkspace: workspace) : nil)
				}
				completionHandler(files)
			} else {
				completionHandler(nil)
			}
		}
	}
	
	/** If importing via drop, call this to to see if the file is acceptable
		parameter info: the drag info
		returns: the drag operation to perform
	*/
	func validateTableViewDrop(_ info:NSDraggingInfo) -> NSDragOperation {
		guard info.draggingSource() == nil else  { return NSDragOperation() } //don't allow local drags
		let urls = info.draggingPasteboard().readObjects(forClasses: [URL.self as! AnyObject.Type], options: pboardReadOptions)
		guard urls?.count > 0 else { return NSDragOperation() } //must have a url
		let acceptableTypes = FileType.importableFileTypes.map() { $0.fileExtension }
		for aUrl in urls! {
			//if not a valid filetype extension, return .None
			if !acceptableTypes.contains((aUrl as AnyObject).pathExtension) { return NSDragOperation() }
		}
		//must be good
		return NSDragOperation.copy
	}
	
	/** If importing via drop, prompts about replacing files if there are any duplicates
		parameter info: the drag info
		parameter workspace: the workspace the file(s) will be imported into
		parameter handler: called with the array of files to import
	*/
	func acceptTableViewDrop(_ info:NSDraggingInfo, workspace:Workspace, window:NSWindow, handler:@escaping ([FileToImport]) -> Void)
	{
		assert(validateTableViewDrop(info) != NSDragOperation(), "validate wasn't called on drag info")
		let urls = info.draggingPasteboard().readObjects(forClasses: [URL.self as! AnyObject.Type], options: pboardReadOptions) as? [URL]
		guard urls?.count > 0 else { return }
		let existingNames = workspace.files.map() { $0.name }
		if urls?.filter({ existingNames.contains($0.lastPathComponent) }).first != nil {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Replace existing file(s)?", comment: "")
			alert.informativeText = NSLocalizedString("One or more files already exist with the same name as a dropped file", comment:"")
			alert.addButton(withTitle: NSLocalizedString("Replace", comment:""))
			alert.addButton(withTitle: NSLocalizedString("Cancel", comment:""))
			let uniqButton = alert.addButton(withTitle: NSLocalizedString("Create Unique Names", comment:""))
			uniqButton.keyEquivalent = "u"
			//following is stupid conversion to bad swift conversion of property. filed radar 24660685
			uniqButton.keyEquivalentModifierMask = NSEventModifierFlags(rawValue: UInt(Int(NSEventModifierFlags.command.rawValue)))
			alert.beginSheetModal(for: window, completionHandler: { response in
				guard response != NSAlertSecondButtonReturn else { return }
				let files = urls!.map() { url in
					FileToImport(url: url, uniqueName: response == NSAlertFirstButtonReturn ? nil : self.uniqueFileName(url.lastPathComponent, inWorkspace: workspace))
				}
				handler(files)
			}) 
		} else {
			handler(urls!.map() { url in FileToImport(url: url, uniqueName: nil) } )
		}
	}
	
	/** generates a unique file name (by adding a number to the end) for a file in a workspace */
	func uniqueFileName(_ desiredName:String, inWorkspace workspace:Workspace) -> String {
		var i = 1
		let nsname = NSString(string:desiredName)
		let baseName = nsname.deletingPathExtension
		let pathExtension = nsname.pathExtension
		var useableName = desiredName
		let existingNames = workspace.files.map() { return $0.name }
		//check if desiredName is ok
		if !existingNames.contains(desiredName) {
			return desiredName
		}
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
