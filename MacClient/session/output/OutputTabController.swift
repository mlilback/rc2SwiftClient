//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import MJLLogger
import Networking
import ClientCore
import ReactiveSwift
import SwiftyUserDefaults

enum OutputTab: Int {
	 case console = 0, preview, webKit, image, help
}

// to allow parent controller to potentially modify contextual menu of a child controller
protocol ContextualMenuDelegate: class {
	func contextMenuItems(for: OutputController) -> [NSMenuItem]
}

protocol OutputController: Searchable {
	var contextualMenuDelegate: ContextualMenuDelegate? { get set }
}

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	// MARK: properties
	@IBOutlet var additionContextMenuItems: NSMenu?
	
	var currentOutputController: OutputController!
	weak var consoleController: ConsoleOutputController?
	weak var previewController: LivePreviewDisplayController?
	weak var imageController: ImageOutputController?
	weak var webController: WebKitOutputController?
	weak var helpController: HelpOutputController?
	weak var searchButton: NSSegmentedControl?
	var previewOutputController: LivePreviewOutputController? { return previewController }
	var imageCache: ImageCache? { return sessionController?.session.imageCache }
	weak var sessionController: SessionController? { didSet { sessionControllerUpdated() } }
	weak var displayedFile: AppFile?
	var searchBarVisible: Bool {
		get { return currentOutputController.searchBarVisible }
		set { currentOutputController.performFind(action: newValue ? .showFindInterface : .hideFindInterface) }
	}
	let selectedOutputTab = MutableProperty<OutputTab>(.console)
	/// temp storage for state to restore because asked to restore before session is set
	private var restoredState: SessionState.OutputControllerState?

	// MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(handleDisplayHelp(_:)), name: .displayHelpTopic, object: nil)
		selectedOutputTab.signal.observeValues { [weak self] tab in
			self?.switchTo(tab: tab)
		}
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		guard consoleController == nil else { return }
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = { [weak self] (fw) in self?.displayAttachment(fw) }
		consoleController?.contextualMenuDelegate = self
		previewController = firstChildViewController(self)
		previewController?.contextualMenuDelegate = self
		imageController = firstChildViewController(self)
		imageController?.imageCache = imageCache
		imageController?.contextualMenuDelegate = self
		webController = firstChildViewController(self)
		webController?.onClear = { [weak self] in
			self?.selectedOutputTab.value = .console
		}
		webController?.contextualMenuDelegate = self
		helpController = firstChildViewController(self)
		helpController?.contextualMenuDelegate = self
		currentOutputController = consoleController
	}
	
	private func sessionControllerUpdated() {
		imageController?.imageCache = imageCache
		DispatchQueue.main.async {
			self.loadSavedState()
		}
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		if let myView = tabView as? OutputTopView {
			myView.windowSetCall = {
				self.hookupToToolbarItems(self, window: myView.window!)
			}
		}
	}
	
	@objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action {
		case #selector(switchToSubView(_:)):
			guard let desiredTab = OutputTab(rawValue: menuItem.tag) else { return false }
			return desiredTab != selectedOutputTab.value
		default: return false
		}
	}
	
	func initialFirstResponder() -> NSResponder {
		return (self.consoleController?.consoleTextField)!
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier.rawValue == "clear" {
			item.target = self
			item.action = #selector(OutputTabController.clearConsole(_:))
			if let myItem = item as? ClearConsoleToolbarItem {
				myItem.textView = consoleController?.resultsView
				myItem.tabController = self
				
			}
			return true
		} else if item.itemIdentifier.rawValue == "search" {
			searchButton = item.view as? NSSegmentedControl
			TargetActionBlock { [weak self] sender in
				self?.toggleSearchBar()
				}.installInControl(searchButton!)
			if let myItem = item as? ValidatingToolbarItem {
				myItem.validationHandler = { [weak self] item in
					item.isEnabled = self?.currentOutputController.supportsSearchBar ?? false
				}
			}
			return true
		}
		return false
	}

	func showHelp(_ topics: [HelpTopic]) {
		guard topics.count > 0 else {
			if let rstr = sessionController?.format(errorString: NSLocalizedString("No Help Found", comment: "")) {
				consoleController?.append(responseString: rstr)
			}
			return
		}
		if topics.count == 1 {
			showHelpTopic(topics[0])
			return
		}
		//TODO: handle prompt for selecting a topic out of topics
		showHelpTopic(topics[0])
	}
	
	@objc func handleDisplayHelp(_ note: Notification) {
		if let topic: HelpTopic = note.object as? HelpTopic {
			showHelpTopic(topic)
		} else if let topicName = note.object as? String {
			showHelp(HelpController.shared.topicsWithName(topicName))
		} else { //told to show without a topic. switch back to console.
			selectedOutputTab.value = .console
		}
	}

	func toggleSearchBar() {
		let action: NSTextFinder.Action = currentOutputController.searchBarVisible ? .hideFindInterface : .showFindInterface
		currentOutputController.performFind(action: action)
	}
	
	@IBAction func clearConsole(_ sender: Any?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
	}

	/// action that switches to the OutputTab specified in a NSMenuItem's tag property
	@IBAction func switchToSubView(_ sender: Any?) {
		guard let mItem = sender as? NSMenuItem, let tab = OutputTab(rawValue: mItem.tag) else { return }
		selectedOutputTab.value = tab
	}
	
	func displayAttachment(_ fileWrapper: FileWrapper) {
		Log.info("told to display file \(fileWrapper.filename!)", .app)
		guard let attachment = try? MacConsoleAttachment.from(data: fileWrapper.regularFileContents!) else {
			Log.warn("asked to display invalid attachment", .app)
			return
		}
		switch attachment.type {
		case .file:
			if let file = sessionController?.session.workspace.file(withId: attachment.fileId) {
				webController?.load(file: file)
				selectedOutputTab.value = .webKit
			} else {
				Log.warn("error getting file attachment to display: \(attachment.fileId)", .app)
				let err = AppError(.fileNoLongerExists)
				presentError(err, modalFor: view.window!, delegate: nil, didPresent: nil, contextInfo: nil)
			}
		case .image:
			if let image = attachment.image {
				imageController?.display(image: image)
				selectedOutputTab.value = .image
				// This might not be necessary
				tabView.window?.toolbar?.validateVisibleItems()
			}
		}
	}
	
	func show(file: AppFile?) {
		//strip optional
		guard let file = file else {
			webController?.clearContents()
			selectedOutputTab.value = .console
			displayedFile = nil
			return
		}
		let url = self.sessionController!.session.fileCache.cachedUrl(file: file)
		guard url.fileSize() > 0 else {
			//caching/download bug. not sure what causes it. recache the file and then call again
			sessionController?.session.fileCache.recache(file: file).observe(on: UIScheduler()).startWithCompleted {
				self.show(file: file)
			}
			return
		}
		displayedFile = file
		// use webkit to handle images the user selected since the imageView only works with images in the cache
		self.selectedOutputTab.value = .webKit
		self.webController?.load(file: file)
	}

	func append(responseString: ResponseString) {
		consoleController?.append(responseString: responseString)
		//switch back to console view if appropriate type
		switch responseString.type {
		case .input, .output, .error:
			if selectedOutputTab.value != .console {
				selectedOutputTab.value = .console
			}
		default:
			break
		}
	}
	
	/// This is called when the current file in the editor has changed.
	/// It should decide if the output view should be changed to match the editor document.
	///
	/// - Parameter editorMode: the mode of the editor
	func considerTabChange(editorMode: EditorMode) {
		switch editorMode {
			case .preview:
				selectedOutputTab.value = .preview
			case .source:
				selectedOutputTab.value = .console
		}
	}

	func handleSearch(action: NSTextFinder.Action) {
		currentOutputController.performFind(action: action)
	}
	
	func save(state: inout SessionState.OutputControllerState) {
		state.selectedTabId = selectedOutputTab.value.rawValue
		state.selectedImageId = imageController?.selectedImageId ?? 0
		consoleController?.save(state: &state)
		webController?.save(state: &state.webViewState)
		helpController?.save(state: &state.helpViewState)
	}
	
	func restore(state: SessionState.OutputControllerState) {
		restoredState = state
	}
	
	/// actually loads the state from instance variable
	func loadSavedState() {
		guard let savedState = restoredState else { return }
		consoleController?.restore(state: savedState)
		if let selTab = OutputTab(rawValue: savedState.selectedTabId)
		{
			self.selectedOutputTab.value = selTab
		}
		let imgId = savedState.selectedImageId
		self.imageController?.display(imageId: imgId)
		webController?.restore(state: savedState.webViewState)
		helpController?.restore(state: savedState.helpViewState)
		restoredState = nil
	}
}

// MARK: - contextual menu delegate
extension OutputTabController: ContextualMenuDelegate {
	func contextMenuItems(for: OutputController) -> [NSMenuItem] {
		// have to return copies of items
		guard let tmpMenu = additionContextMenuItems?.copy() as? NSMenu else { return [] }
		return tmpMenu.items
	}
}

// MARK: - private methods
private extension OutputTabController {
	/// should only ever be called via the closure for selectedOutputTab.signal.observeValues set in viewDidLoad.
	func switchTo(tab: OutputTab) {
		selectedTabViewItemIndex = tab.rawValue
		switch selectedOutputTab.value {
		case .console:
			currentOutputController = consoleController
		case .preview:
			currentOutputController = previewController
		case .image:
			currentOutputController = imageController
		case .webKit:
			currentOutputController = webController
		case .help:
			currentOutputController = helpController
		}
		if view.window?.firstResponder == nil {
			view.window?.makeFirstResponder(currentOutputController as? NSResponder)
		}
	}
	
	///actually shows the help page for the specified topic
	func showHelpTopic(_ topic: HelpTopic) {
		selectedOutputTab.value = .help
		helpController!.loadHelpTopic(topic)
	}
}

// MARK: - helper classes
class OutputTopView: NSTabView {
	var windowSetCall: (() -> Void)?
	override func viewDidMoveToWindow() {
		if self.window != nil {
			windowSetCall?()
		}
		windowSetCall = nil
	}
}

class ClearConsoleToolbarItem: NSToolbarItem {
	var textView: NSTextView?
	weak var tabController: NSTabViewController?
	override func validate() {
		guard let textLength = textView?.textStorage?.length else { isEnabled = false; return }
		isEnabled = textLength > 0 && tabController?.selectedTabViewItemIndex == 0
	}
}

class OutputConsoleToolbarItem: NSToolbarItem {
	weak var tabController: NSTabViewController?
	override func validate() {
		guard let tabController = tabController else { return }
		isEnabled = tabController.selectedTabViewItemIndex > 0
	}
}
