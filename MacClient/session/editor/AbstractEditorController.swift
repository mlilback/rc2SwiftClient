//
//  AbstractEditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import SyntaxParsing
import MJLLogger
import ReactiveSwift

class AbstractEditorController: AbstractSessionViewController, CodeEditor {
	private(set) var context: EditorContext?
	
	@objc dynamic var canExecute: Bool {
		guard context?.currentDocument.value?.isLoaded ?? false else { return false }
		return context?.currentDocument.value?.currentContents?.count ?? 0 > 0
	}
	
	func setContext(context: EditorContext) {
		precondition(self.context == nil)
		self.context = context
		let ncenter = context.notificationCenter
		ncenter.addObserver(self, selector: .autoSave, name: NSApplication.didResignActiveNotification, object: NSApp)
		ncenter.addObserver(self, selector: .autoSave, name: NSApplication.willTerminateNotification, object: NSApp)
		ncenter.addObserver(self, selector: #selector(documentWillSave(_:)), name: .willSaveDocument, object: nil)
		context.workspaceNotificationCenter.addObserver(self, selector: #selector(autosaveCurrentDocument), name: NSWorkspace.willSleepNotification, object: context.workspaceNotificationCenter)
		context.currentDocument.signal.observeValues { [weak self] newDoc in
			self?.documentChanged(newDocument: newDoc)
		}
	}

	///actually implements running a query, saving first if document is dirty
	func executeSource(type: ExecuteType) {
		guard let currentDocument = context?.currentDocument.value else {
			fatalError("runQuery called with no file selected")
		}
		let file = currentDocument.file
		guard currentDocument.isDirty else {
			Log.debug("executeQuery executing without save", .app)
			session.execute(file: file, type: type)
			return
		}
		saveWithProgress().startWithResult { result in
			if let innerError = result.error {
				let appError = AppError(.saveFailed, nestedError: innerError)
				Log.info("save for execute returned an error: \(result.error!)", .app)
				self.appStatus?.presentError(appError.rc2Error, session: self.session)
				return
			}
			Log.info("executeQuery saved file, now executing", .app)
			self.session.execute(file: file, type: type)
		}
	}

	@objc func autosaveCurrentDocument() {
		guard context?.currentDocument.value?.isDirty ?? false else { return }
		saveWithProgress(isAutoSave: true).startWithResult { result in
			guard result.error == nil else {
				Log.warn("autosave failed: \(result.error!)", .session)
				return
			}
			//need to do anything when successful?
		}
	}
	
	@objc func documentWillSave(_ notification: Notification) {
	}

	//should be the only place an actual save is performed
	func saveWithProgress(isAutoSave: Bool = false) -> SignalProducer<Bool, Rc2Error> {
		guard let context = context else { fatalError() }
		guard let doc = context.currentDocument.value else {
			return SignalProducer<Bool, Rc2Error>(error: Rc2Error(type: .logic, severity: .error, explanation: "save called with nothing to save"))
		}
		return context.save(document: doc, isAutoSave: isAutoSave)
			.map { _ in return true }
			.updateProgress(status: self.appStatus!, actionName: "Save document")
			.observe(on: UIScheduler())
	}

	func documentChanged(newDocument: EditorDocument?) {
		guard let document = newDocument else { return }
		if document.isLoaded {
			loaded(document: document, content: document.currentContents ?? "")
		} else {
			session.fileCache.contents(of: document.file).observe(on: UIScheduler()).startWithResult { result in
				guard let data = result.value else  {
					self.appStatus?.presentError(result.error!, session: self.session)
					return
				}
				self.loaded(document: document, content: String(data: data, encoding: .utf8)!)
			}
		}
	}

	func loaded(document: EditorDocument, content: String) {
		fatalError("subclass must implement, not call super")
	}

	@IBAction func runQuery(_ sender: AnyObject?) {
		executeSource(type: .run)
	}
	
	@IBAction func sourceQuery(_ sender: AnyObject?) {
		executeSource(type: .source)
	}
	
}
