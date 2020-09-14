//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger
import ReactiveSwift
import Networking
import Rc2Common

private let minTimeBetweenAutoSaves: TimeInterval = 2

/// An EditorDocument wraps a AppFile, UndoManager, and contents as a String
public class EditorDocument: NSObject {
	public private(set) var file: AppFile
	public let undoManager: UndoManager
	/// index of contents at top of scroll view
	public var topVisibleIndex: Int = 0
	/// state of the notebook when this document was last used
	public private(set) var lastSaveTime: TimeInterval = 0
	/// the contents the last time it was saved
	public private(set) var savedContents: String?
	/// contents with changes that haven't been saved
	public let editedContents = MutableProperty<String?>("")
	public private(set) var isLoaded: Bool = false
	public var isRmarkdown: Bool { return file.fileType.fileExtension == "Rmd" }
	public var isRDocument: Bool { return file.fileType.fileExtension == "R" }

	/// only returns true for Rmd files
	public var parsable: Bool { return file.fileType.fileExtension == "Rmd" }
	
	/// If the document has been edited, the editedContents. Otherwise, the saved Contents
	public var currentContents: String? {
		return editedContents.value == nil ? savedContents : editedContents.value
	}
	
	/// true if the editedContents are differernt from the savedContent
	public var isDirty: Bool {
		if nil == editedContents.value { return false }
		return editedContents.value != savedContents
	}
	
	/// Initialize a new EditorDocument
	/// - Parameter file: The file whose content this document represents
	public init(file: AppFile) {
		self.file = file
		self.undoManager = UndoManager()
		super.init()
	}
	
	/// sets the savedContent value, clears any editied content, and marks document as loaded
	///
	/// - Parameter contents: the saved content of the file
	func contentsLoaded(contents: String) {
		savedContents = contents
		editedContents.value = nil
		isLoaded = true
		lastSaveTime = Date.timeIntervalSinceReferenceDate
	}
	
	/// resets clears out the cached contents and marks as not loaded
	public func fileUpdated() {
		guard isLoaded else { return }
		isLoaded = false
		savedContents = nil
		editedContents.value = nil
	}
	
	/// sets savedContents to currentContents and updates the lastSaveTime
	public func contentsSaved() {
		savedContents = currentContents
		editedContents.value = nil
		lastSaveTime = Date.timeIntervalSinceReferenceDate
	}
}
