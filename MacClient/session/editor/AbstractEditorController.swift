//
//  AbstractEditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import ClientCore
import Networking
import SyntaxParsing
import MJLLogger
import ReactiveSwift

///selectors used in this file, aliased with shorter, descriptive names
extension Selector {
	static let runQuery = #selector(SourceEditorController.runQuery(_:))
	static let sourceQuery = #selector(SourceEditorController.sourceQuery(_:))
	static let findPanelAction = #selector(NSTextView.performFindPanelAction(_:))
	static let executeLine = #selector(SourceEditorController.executeCurrentLine(_:))
}

/// base class for editor controllers. Subclasses must implement loaded() and editsNeedSaving()
class AbstractEditorController: AbstractSessionViewController, MacCodeEditor {
	// MARK: properties
	private(set) var context: EditorContext?
	private var autoSaveDisposable = Atomic<Disposable?>(nil)
	/// contents are disposed when the document changes
	private(set) var compositeDisposable = CompositeDisposable()
	/// used internally to prevent responding to a change made by self
	private var ignoreContentChanges = false
	
	/// checks if document is loaded and is not empty
	@objc dynamic var canExecute: Bool {
		guard context?.currentDocument.value?.isLoaded ?? false else { return false }
		return context?.currentDocument.value?.currentContents?.count ?? 0 > 0
	}
	
	/// for subclasses to override
	var documentDirty: Bool { return false }
	
	// MARK: - standard
	override func viewWillDisappear() {
		super.viewWillDisappear()
		autosaveCurrentDocument()
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action {
		case #selector(save(_:)):
			return documentDirty
		case #selector(revert(_:)):
			return documentDirty
		default:
			return false
		}
	}
	
	// MARK: - actions
	@IBAction func save(_ sender: Any?) {
		saveWithProgress().startWithResult { result in
			if let innerError = result.error {
				let appError = AppError(.saveFailed, nestedError: innerError)
				Log.info("save for execute returned an error: \(result.error!)", .app)
				self.appStatus?.presentError(appError.rc2Error, session: self.session)
				return
			}
		}
	}
	
	@IBAction func revert(_ sender: Any?) {
		guard let doc = context?.currentDocument.value else { return }
		// Do you want to revert the document “AbstractEditorController.swift” to the last saved version?
		confirmAction(message: "Do you want to revert the document \"\(doc.file.name)\" to the last saved version?", infoText: "", buttonTitle: "Revert") { confirmed in
			guard confirmed else { return }
			self.context?.revertCurrentDocument()
		}
	}
	
	@IBAction func runQuery(_ sender: AnyObject?) {
		executeSource(type: .run)
	}
	
	@IBAction func sourceQuery(_ sender: AnyObject?) {
		executeSource(type: .source)
	}
	
	// MARK: - internal
	/// called when document's editedContents is changed by something besides this object
	private func editedContentsChanged(updatedContents: String) {
		guard !ignoreContentChanges else { return }
		loaded(content: updatedContents)
	}
	
	/// for subclasses to call to save edits. loaded will not be called, which would happen if a subclass set the document's editedContents directly
	func save(edits: String) {
		// prevent recursion
		guard !ignoreContentChanges else { return }
		ignoreContentChanges = true
		context?.currentDocument.value?.editedContents.value = edits
		ignoreContentChanges = false
	}
	
	/// called after view loaded with injected data
	func setContext(context: EditorContext) {
		precondition(self.context == nil)
		self.context = context
		let ncenter = context.notificationCenter
		let autoSave = #selector(autosaveCurrentDocument)
		// don't enable autsave on backgrounding while running in the debugger or else can't debug saving
		if !AppInfo.amIBeingDebugged {
			ncenter.addObserver(self, selector: autoSave, name: NSApplication.didResignActiveNotification, object: NSApp)
		}
		ncenter.addObserver(self, selector: autoSave, name: NSApplication.willTerminateNotification, object: NSApp)
		ncenter.addObserver(self, selector: #selector(documentWillSave(_:)), name: .willSaveDocument, object: nil)
		context.workspaceNotificationCenter.addObserver(self, selector: autoSave, name: NSWorkspace.willSleepNotification, object: context.workspaceNotificationCenter)
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
	
	// called by notifications when sleeping/backgrounding
	@objc func autosaveCurrentDocument() {
		// return if autosave in progress or no document
		guard autoSaveDisposable.value == nil,
			let doc = context?.currentDocument.value
			else { return }
		// don't save if have saved in last half a second
		guard Date.timeIntervalSinceReferenceDate - doc.lastSaveTime > 0.5 else { return }
		editsNeedSaving()
		guard UserDefaults.standard[.autosaveEnabled] else { return }
		autoSaveDisposable.value?.dispose()
		autoSaveDisposable.value = context?.save(document: doc, isAutoSave: true)
			.updateProgress(status: self.appStatus, actionName: "Autosave")
			.observe(on: UIScheduler())
			.startWithCompleted { [weak self] in
				self?.autoSaveDisposable.value?.dispose()
				self?.autoSaveDisposable.value = nil
		}
	}
	
	/// called before document is about to be saved
	@objc private func documentWillSave(_ notification: Notification) {
		editsNeedSaving()
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

	/// called when the current document changes
	func documentChanged(newDocument: EditorDocument?) {
		compositeDisposable.dispose()
		compositeDisposable = CompositeDisposable()
		guard let document = newDocument else { return }
		if document.isLoaded {
			compositeDisposable += document.editedContents.signal.observeValues { [weak self] contents in
				guard let me = self else { return }
				me.editedContentsChanged(updatedContents: document.currentContents ?? "")
			}
			loaded(content: document.currentContents ?? "")
		} else {
			session.fileCache.contents(of: document.file).observe(on: UIScheduler()).startWithResult { result in
				guard let data = result.value else  {
					self.appStatus?.presentError(result.error!, session: self.session)
					return
				}
				self.compositeDisposable += document.editedContents.signal.observeValues { [weak self] contents in
					self?.editedContentsChanged(updatedContents: contents ?? "")
				}
				self.loaded(content: String(data: data, encoding: .utf8)!)
			}
		}
	}

//	/// applies current theme to the targetString which should have been parsed
//-	func updateSyntaxStyle(targetString: NSMutableAttributedString) {
//		let theme = ThemeManager.shared.activeSyntaxTheme.value
//		let fullRange = targetString.string.fullNSRange
//		targetString.addAttribute(.font, value: context!.editorFont.value, range: fullRange)
//		targetString.removeAttribute(.foregroundColor, range: fullRange)
//		targetString.removeAttribute(.backgroundColor, range: fullRange)
//		targetString.enumerateAttributes(in: fullRange, options: []) { (keyValues, attrRange, stop) in
//			if let fragmentType = keyValues[FragmentTypeKey] as? FragmentType {
//				self.style(fragmentType: fragmentType, in: targetString, range: attrRange, theme: theme)
//			}
//			if let chunkType = keyValues[ChunkTypeKey] as? ChunkType {
//				switch chunkType {
//				case .code:
//					targetString.addAttribute(.backgroundColor, value: theme.color(for: .codeBackground), range: attrRange)
//				case .equation:
//					targetString.addAttribute(.backgroundColor, value: theme.color(for: .equationBackground), range: attrRange)
//				case .docs:
//					break
//				}
//			}
//		}
//	}
//
//	/// updates the style attributes for a fragment in an attributed string
//-	private func style(fragmentType: FragmentType, in text: NSMutableAttributedString, range: NSRange, theme: SyntaxTheme) {
//		switch fragmentType {
//		case .none:
//			break
//		case .quote:
//			text.addAttribute(.foregroundColor, value: theme.color(for: .quote), range: range)
//		case .comment:
//			text.addAttribute(.foregroundColor, value: theme.color(for: .comment), range: range)
//		case .keyword:
//			text.addAttribute(.foregroundColor, value: theme.color(for: .keyword), range: range)
//		case .symbol:
//			text.addAttribute(.foregroundColor, value: theme.color(for: .symbol), range: range)
//		case .number:
//			break
//		}
//	}
	
	/// called after the current document has changed. called by documentChanged() after the contents have been loaded from disk/network. Subclasses must override.
	func loaded(content: String) {
		fatalError("subclass must implement, not call super")
	}

	/// subclasses should override and save contents via save(edits:). super should not be called
	func editsNeedSaving() {
		fatalError("subclasses must implement, not call super")
	}
	
}
