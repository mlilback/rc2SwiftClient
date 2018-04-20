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

fileprivate let minTimeBetweenAutoSaves: TimeInterval = 2

/// used for the notebook to save its state for a document
public struct NotebookState: Codable {
	public let selectionPath: IndexPath
	/// nil if frontmatter and indexPath is zero
	public let selectionType: TemplateType?
	
	public init(path: IndexPath, type: TemplateType?) {
		self.selectionPath = path
		self.selectionType = type
	}
}

public class EditorDocument: NSObject {
	public private(set) var file: AppFile
	private var fileUrl: URL
	public let undoManager: UndoManager
	/// index of contents at top of scroll view
	public var topVisibleIndex: Int = 0
	/// state of the notebook when this document was last used
	public var notebookState: NotebookState?
	var lastSaveTime: TimeInterval = 0
	public private(set) var savedContents: String?
	public var editedContents: String?
	public private(set) var isLoaded: Bool = false
	
	public var parsable: Bool { return file.fileType.fileExtension == "Rmd" }
	
	public var currentContents: String? {
		return editedContents == nil ? savedContents : editedContents
	}
	
	public var isDirty: Bool {
		if nil == editedContents { return false }
		return editedContents != savedContents
	}
	
	public init(file: AppFile, fileUrl: URL) {
		self.file = file
		self.fileUrl = fileUrl
		self.undoManager = UndoManager()
	}
	
	/// sets the savedContent value, clears any editied content, and marks document as loaded
	///
	/// - Parameter contents: the saved content of the file
	func contentsLoaded(contents: String) {
		savedContents = contents
		editedContents = nil
		isLoaded = true
		lastSaveTime = Date.timeIntervalSinceReferenceDate
	}
	
	/// resets clears out the cached contents and marks as not loaded
	public func fileUpdated() {
		guard isLoaded else { return }
		isLoaded = false
		savedContents = nil
		editedContents = nil
	}
	
	/// sets savedContents to currentContents and updates the lastSaveTime
	public func contentsSaved() {
		savedContents = currentContents
		editedContents = nil
		lastSaveTime = Date.timeIntervalSinceReferenceDate
	}
}
