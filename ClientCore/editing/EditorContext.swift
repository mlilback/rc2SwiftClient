//
//  EditorContext.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import Networking
import ReactiveSwift
import SyntaxParsing
import Rc2Common

/// object passed to UI controllers that take part in editing a document. Any values that might need to be observed for changes are declared as ReactiveSwift Properties.
public protocol EditorContext: class {
	/// the current EditorDocument. Signals are processed synchronously on the calling thread
	var currentDocument: Property<EditorDocument?> { get }
	/// the parsed version of the currentDocument. This property is updated on a main loop cycle after the currentDocument
	var parsedDocument: Property<RmdDocument?> { get }
	/// the user-selected font for any editing task
	var editorFont: MutableProperty<PlatformFont> { get }
	/// an error handler to propagate non-fatal errors that are not generated by a Signal(Producer)
	var errorHandler: Rc2ErrorHandler { get }
	/// the notification center to use for posting Notifications. Provides dependency injection to replace use of the system singleton
	var notificationCenter: NotificationCenter { get }
	/// the workspace notification center to use for observing Notifications such as sleep/wake (macOS only). Provides dependency injection to replace use of the system singleton
	var workspaceNotificationCenter: NotificationCenter { get }
	/// the ReactiveSwift lifetime to use for any observers related to this EditorContext
	var lifetime: Lifetime { get }
	/// the DocType of the current document
	var docType: DocType { get }
	
	/// Generates an image to use for the passed in latex, size based on the editor font's size
	///
	/// - Parameter latex: The latex to use as an inline equation
	/// - Returns: an image of the latex as an inline equation
	func inlineImageFor(latex: String) -> PlatformImage?
	
	/// Saves a document
	///
	/// - Parameters:
	///   - document: the document to save
	///   - isAutoSave: true if an autosave, false if a user-initiated save
	/// - Returns: a SignalProducer that returns an empty value or an error
	func save(document: EditorDocument, isAutoSave: Bool) -> SignalProducer<(), Rc2Error>
	
	/// Reverts the current document to last saved contents
	func revertCurrentDocument()
	
	/// Reparses the current document using the currentContents
	func parseCurrentDocument()
}

public extension EditorContext {
	var docType: DocType {
		guard let fileExt = currentDocument.value?.file.fileType.fileExtension else { return .none }
		switch fileExt {
		case "Rmd": return .rmd
		case "Rnw": return .latex
		default: return .none
		}
	}
}

