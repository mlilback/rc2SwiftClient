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

class AbstractEditorController: AbstractSessionViewController, MacCodeEditor {
	private(set) var context: EditorContext?
	private var autoSaveDisposable = Atomic<Disposable?>(nil)
	
	@objc dynamic var canExecute: Bool {
		guard context?.currentDocument.value?.isLoaded ?? false else { return false }
		return context?.currentDocument.value?.currentContents?.count ?? 0 > 0
	}
	
	var documentDirty: Bool { return false }
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action {
		case #selector(save(_:)):
			return documentDirty
		case #selector(revert(_:)):
			return documentDirty
		default:
			return super.validateMenuItem(menuItem)
		}
	}
	
	func setContext(context: EditorContext) {
		precondition(self.context == nil)
		self.context = context
		let ncenter = context.notificationCenter
		let autoSave = #selector(autosaveCurrentDocument)
		ncenter.addObserver(self, selector: autoSave, name: NSApplication.didResignActiveNotification, object: NSApp)
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
		guard UserDefaults.standard[.autosaveEnabled] else { return }
		autoSaveDisposable.value?.dispose()
		autoSaveDisposable.value = context?.save(document: doc, isAutoSave: true)
			.updateProgress(status: self.appStatus!, actionName: "Autosave")
			.observe(on: UIScheduler())
			.startWithCompleted { [weak self] in
				self?.autoSaveDisposable.value?.dispose()
				self?.autoSaveDisposable.value = nil
			}
//		guard context?.currentDocument.value?.isDirty ?? false else { return }
//		saveWithProgress(isAutoSave: true).startWithResult { result in
//			guard result.error == nil else {
//				Log.warn("autosave failed: \(result.error!)", .session)
//				return
//			}
//			//need to do anything when successful?
//		}
	}
	
	@objc func documentWillSave(_ notification: Notification) {
	}

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
			loaded(content: document.currentContents ?? "")
		} else {
			session.fileCache.contents(of: document.file).observe(on: UIScheduler()).startWithResult { result in
				guard let data = result.value else  {
					self.appStatus?.presentError(result.error!, session: self.session)
					return
				}
				self.loaded(content: String(data: data, encoding: .utf8)!)
			}
		}
	}

	/// applies current theme to the targetString which should have been parsed
	func updateSyntaxStyle(targetString: NSMutableAttributedString) {
		let theme = ThemeManager.shared.activeSyntaxTheme.value
		let fullRange = targetString.string.fullNSRange
		targetString.addAttribute(.font, value: context!.editorFont.value, range: fullRange)
		targetString.removeAttribute(.foregroundColor, range: fullRange)
		targetString.removeAttribute(.backgroundColor, range: fullRange)
		targetString.enumerateAttributes(in: fullRange, options: []) { (keyValues, attrRange, stop) in
			if let fragmentType = keyValues[FragmentTypeKey] as? FragmentType {
				self.style(fragmentType: fragmentType, in: targetString, range: attrRange, theme: theme)
			}
			if let chunkType = keyValues[ChunkTypeKey] as? ChunkType {
				switch chunkType {
				case .code:
					targetString.addAttribute(.backgroundColor, value: theme.color(for: .codeBackground), range: attrRange)
				case .equation:
					targetString.addAttribute(.backgroundColor, value: theme.color(for: .equationBackground), range: attrRange)
				case .docs:
					break
				}
			}
		}
	}
	
	private func style(fragmentType: FragmentType, in text: NSMutableAttributedString, range: NSRange, theme: SyntaxTheme) {
		switch fragmentType {
		case .none:
			break
		case .quote:
			text.addAttribute(.foregroundColor, value: theme.color(for: .quote), range: range)
		case .comment:
			text.addAttribute(.foregroundColor, value: theme.color(for: .comment), range: range)
		case .keyword:
			text.addAttribute(.foregroundColor, value: theme.color(for: .keyword), range: range)
		case .symbol:
			text.addAttribute(.foregroundColor, value: theme.color(for: .symbol), range: range)
		case .number:
			break
		}
	}
	
	func loaded(content: String) {
		fatalError("subclass must implement, not call super")
	}

	@IBAction func runQuery(_ sender: AnyObject?) {
		executeSource(type: .run)
	}
	
	@IBAction func sourceQuery(_ sender: AnyObject?) {
		executeSource(type: .source)
	}
	
}
