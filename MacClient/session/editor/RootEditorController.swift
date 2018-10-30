//
//  EditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import MJLLogger
import ReactiveSwift

fileprivate extension NSStoryboard.SceneIdentifier {
	static let editorTabController = NSStoryboard.SceneIdentifier("editorTabController")
}

class RootEditorController: AbstractSessionViewController, ToolbarItemHandler {
	// MARK: properties
	@IBOutlet var contentView: NSView!
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	var documentManager: DocumentManager!
	var tabController: NSTabViewController!
	var previewEditor: LivePreviewEditorController!
	var sourceEditor: SourceEditorController!
	var notebookEditor: NotebookEditorController!
	/// the current editor, either sourceEditor or notebookEditor
	var currentEditor: AbstractEditorController?
	/// store for KVO tokens
	private var observerTokens = [Any]()
	// toolbar mode buttons
	var toolbarModeButtons: NSSegmentedControl?
	var toolbarSearchButton: NSSegmentedControl?
	
	@objc dynamic private(set) var notebookModeEnabled: Bool = false { didSet {
		toolbarModeButtons?.setEnabled(notebookModeEnabled, forSegment: 0)
		if !notebookModeEnabled && currentEditor == notebookEditor {
			switchMode(.source)
		}
	} }

	@objc dynamic private(set) var previewModeEnabled: Bool = false { didSet {
		toolbarModeButtons?.setEnabled(previewModeEnabled, forSegment: 2)
		if !previewModeEnabled && currentEditor != previewEditor {
			switchMode(.preview)
		}
	} }

	// MARK: methods
	override func sessionChanged() {
		guard sessionOptional != nil else { return }
		documentManager = DocumentManager(fileSaver: session, fileCache: session.fileCache, lifetime: session.lifetime)
		switchMode(.source)
		setContext(context: documentManager)
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		guard let sboard = self.storyboard else { fatalError("no storyboard? ") }
		// for some reason won't compile if directly setting tabController
		let controller: NSTabViewController = embedViewController(storyboard: sboard, identifier: .editorTabController, contentView: contentView)
		tabController = controller
		let tabChildren = tabController.childViewControllers
		sourceEditor = tabChildren.first(where: { $0 is SourceEditorController } ) as? SourceEditorController
		notebookEditor = tabChildren.first(where: { $0 is NotebookEditorController } ) as? NotebookEditorController
		previewEditor = tabChildren.first(where: { $0 is LivePreviewEditorController } ) as? LivePreviewEditorController
		currentEditor = sourceEditor
		// listen for canExecute changes of actual editors
		observerTokens.append(sourceEditor.observe(\.canExecute, options: [.initial]) { [weak self] object, change in
			guard let me = self, let current = me.currentEditor, current == object else { return }
			me.willChangeValue(forKey: "canExecute")
			me.didChangeValue(forKey: "canExecute")
		})
		observerTokens.append(notebookEditor.observe(\.canExecute, options: [.initial]) { [weak self] object, change in
			guard let me = self, let current = me.currentEditor, current == object else { return }
			me.willChangeValue(forKey: "canExecute")
			me.didChangeValue(forKey: "canExecute")
		})
		observerTokens.append(previewEditor.observe(\.canExecute, options: [.initial]) { [weak self] object, change in
			guard let me = self, let current = me.currentEditor, current == object else { return }
			me.willChangeValue(forKey: "canExecute")
			me.didChangeValue(forKey: "canExecute")
		})
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		self.hookupToToolbarItems(self, window: view.window!)
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier.rawValue == "customEditor" {
			guard let modeButtons = item.view?.viewWithTag(1) as? NSSegmentedControl else { fatalError() }
			guard let searchButton = item.view?.viewWithTag(2) as? NSSegmentedControl else { fatalError() }
			toolbarModeButtons = modeButtons
			toolbarSearchButton = searchButton
			modeButtons.setSelected(true, forSegment: 1)
			TargetActionBlock { [weak self] sender in
				self?.switchMode(EditorMode(rawValue: modeButtons.selectedSegment)!)
			}.installInControl(modeButtons)
			TargetActionBlock { [weak self] sender in
				self?.toggleSearch()
			}.installInControl(searchButton)
			if let myItem = item as? ValidatingToolbarItem {
				myItem.validationHandler = { [weak self] item in
					item.isEnabled = true
					searchButton.setEnabled(self?.documentLoaded ?? false, forSegment: 0)
				}
			}
			return true
		}
		return false
	}

	func toggleSearch() {
		guard let editor = currentEditor else { return }
		let action: NSTextFinder.Action = editor.searchBarVisible ? .hideFindInterface : .showFindInterface
		editor.performFind(action: action)
	}
	
	func switchMode(_ mode: EditorMode) {
		currentEditor = mode == .notebook ? notebookEditor : (mode == .source ? sourceEditor : previewEditor)
		tabController.selectedTabViewItemIndex = mode.rawValue
		toolbarModeButtons?.selectedSegment = mode.rawValue
	}
	
	@IBAction func runQuery(_ sender: Any?) {
		executeSource(type: .run)
	}
	
	@IBAction func sourceQuery(_ sender: Any?) {
		executeSource(type: .source)
	}
}

extension RootEditorController: Searchable {
	var searchableTextView: NSTextView? { return currentEditor?.searchableTextView }
	var supportsSearchBar: Bool { return true }
}

extension RootEditorController: EditorManager {
	@objc dynamic var documentLoaded: Bool { return documentManager.currentDocument.value?.isLoaded ?? false }
	@objc dynamic var canExecute: Bool { return currentEditor?.canExecute ?? false }
	@objc dynamic var canSwitchToNotebookMode: Bool { return notebookModeEnabled && currentEditor != notebookEditor }
	@objc dynamic var canSwitchToSourceMode: Bool { return currentEditor != sourceEditor }
	@objc dynamic var canSwitchToPreviewMode: Bool { return currentEditor != previewEditor }

	func switchTo(mode: EditorMode) {
		switchMode(mode)
	}
	
	func executeSource(type: ExecuteType) {
		currentEditor?.executeSource(type: type)
	}
	
	func save(state: inout SessionState.EditorState) {
		let fontDesc = documentManager.editorFont.value.fontDescriptor
		state.editorFontDescriptor = NSKeyedArchiver.archivedData(withRootObject: fontDesc)
	}
	
	func restore(state: SessionState.EditorState) {
		if let fontData = state.editorFontDescriptor,
			let fontDesc = NSKeyedUnarchiver.unarchiveObject(with: fontData) as? NSFontDescriptor,
			let font = NSFont(descriptor: fontDesc, size: fontDesc.pointSize)
		{
			documentManager.editorFont.value = font
		}
	}
	
	func setContext(context: EditorContext) {
		sourceEditor.setContext(context: context)
		notebookEditor.setContext(context: context)
		previewEditor.setContext(context: context)
	}
	
	func fileChanged(file: AppFile?) {
		documentManager.load(file: file).observe(on: UIScheduler()).startWithResult { result in
			guard result.error == nil else {
				self.appStatus?.presentError(result.error!, session: self.session)
				return
			}
			self.willChangeValue(forKey: "canExecute")
//			sourceEditor.fileChanged(file: file)
//			self.notebookEditor.fileChanged(file: file)
			self.didChangeValue(forKey: "canExecute")
			self.fileNameField?.stringValue = file == nil ? "" : file!.name
			self.notebookModeEnabled = file?.fileType.fileExtension ?? "" == "Rmd"
			self.toolbarModeButtons?.selectedSegment = self.currentEditor == self.notebookEditor ? 0 : 1
		}
	}
}

// MARK: UsesAdjustableFont
extension RootEditorController: UsesAdjustableFont {
	var currentFontDescriptor: NSFontDescriptor {
		get { return documentManager.editorFont.value.fontDescriptor }
		set { documentManager.editorFont.value = NSFont(descriptor: newValue, size: newValue.pointSize)! }
	}
	func fontsEnabled() -> Bool {
		return true
	}
	
	func fontChanged(_ menuItem: NSMenuItem) {
		Log.info("font changed: \((menuItem.representedObject as? NSObject)!)", .app)
		guard let newNameDesc = menuItem.representedObject as? NSFontDescriptor else { return }
		let newDesc = newNameDesc.withSize(documentManager.editorFont.value.pointSize)
		guard let newFont = NSFont(descriptor: newDesc, size: newDesc.pointSize) else { fatalError() }
		documentManager.editorFont.value = newFont
	}
}
