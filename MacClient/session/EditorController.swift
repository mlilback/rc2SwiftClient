//
//  EditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking

fileprivate extension NSStoryboard.SceneIdentifier {
	static let editorTabController = NSStoryboard.SceneIdentifier("editorTabController")
}

enum EditorMode: Int {
	case notebook = 0
	case source
}

class EditorController: AbstractSessionViewController, ToolbarItemHandler {
	
	@IBOutlet var contentView: NSView!
	@IBOutlet var runButton: NSButton?
	@IBOutlet var sourceButton: NSButton?
	@IBOutlet var fileNameField: NSTextField?
	@IBOutlet var contextualMenuAdditions: NSMenu?
	var tabController: NSTabViewController!
	var sourceEditor: SourceEditorController!
	var notebookEditor: NotebookEditorController!
	/// the current editor, either sourceEditor or notebookEditor
	var currentEditor: (AbstractSessionViewController & CodeEditor)?
	/// store for KVO tokens
	private var observerTokens = [Any]()
	// toolbar mode buttons
	var toolbarModeButtons: NSSegmentedControl?
	
	@objc dynamic private(set) var notebookModeEnabled: Bool = false { didSet {
		toolbarModeButtons?.setEnabled(notebookModeEnabled, forSegment: 0)
		if !notebookModeEnabled && currentEditor == notebookEditor {
			switchMode(.source)
		}
	} }
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let sboard = NSStoryboard(name: .mainController, bundle: nil)
		// for some reason won't compile if directly setting tabController
		let controller: NSTabViewController = embedViewController(storyboard: sboard, identifier: .editorTabController, contentView: contentView)
		tabController = controller
		sourceEditor = tabController.childViewControllers.first(where: { $0 is SourceEditorController } ) as! SourceEditorController
		notebookEditor = tabController.childViewControllers.first(where: { $0 is NotebookEditorController } ) as! NotebookEditorController
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
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		self.hookupToToolbarItems(self, window: view.window!)
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier.rawValue == "editorMode" {
			guard let modeButtons = item.view as? NSSegmentedControl else { fatalError() }
			toolbarModeButtons = modeButtons
			TargetActionBlock { [weak self] sender in
				self?.switchMode(EditorMode(rawValue: modeButtons.selectedSegment)!)
				}.installInControl(modeButtons)
			if let myItem = item as? ValidatingToolbarItem {
				myItem.validationHandler = { item in
					item.isEnabled = true
					modeButtons.setEnabled(self.notebookModeEnabled, forSegment: 0)
				}
			}
			return true
		}
		return false
	}

	func switchMode(_ mode: EditorMode) {
		currentEditor = mode == .notebook ? notebookEditor : sourceEditor
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

extension EditorController: CodeEditor {
	@objc dynamic var canExecute: Bool { return currentEditor?.canExecute ?? false }

	func executeSource(type: ExecuteType) {
		currentEditor?.executeSource(type: type)
	}
	
	func save(state: inout SessionState.EditorState) {
		sourceEditor.save(state: &state)
		notebookEditor.save(state: &state)
	}
	
	func restore(state: SessionState.EditorState) {
		sourceEditor.restore(state: state)
		notebookEditor.restore(state: state)
	}
	
	func fileChanged(file: AppFile?) {
		willChangeValue(forKey: "canExecute")
		sourceEditor.fileChanged(file: file)
		notebookEditor.fileChanged(file: file)
		didChangeValue(forKey: "canExecute")
		fileNameField?.stringValue = file == nil ? "" : file!.name
		notebookModeEnabled = file?.fileType.fileExtension ?? "" == "Rmd"
		toolbarModeButtons?.selectedSegment = currentEditor == notebookEditor ? 0 : 1
	}
	
}
