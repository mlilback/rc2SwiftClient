//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import MJLLogger
import Networking
import ReactiveSwift
import ReactiveCocoa
import Result
import SwiftyUserDefaults

enum OutputTab: Int {
	 case console = 0, image, webKit, help
}

protocol OutputController: Searchable {
}

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	// MARK: properties
	var currentOutputController: OutputController!
	weak var consoleController: ConsoleOutputController?
	weak var imageController: ImageOutputController?
	weak var webController: WebKitOutputController?
	weak var helpController: HelpOutputController?
	weak var searchButton: NSSegmentedControl?
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
		imageController = firstChildViewController(self)
		imageController?.imageCache = imageCache
		webController = firstChildViewController(self)
		webController?.onClear = { [weak self] in
			self?.selectedOutputTab.value = .console
		}
		helpController = firstChildViewController(self)
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
	
	@objc func clearConsole(_ sender: AnyObject?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
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

// MARK: - private methods
private extension OutputTabController {
	func switchTo(tab: OutputTab) {
		selectedTabViewItemIndex = tab.rawValue
		switch selectedOutputTab.value {
		case .console:
			currentOutputController = consoleController
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
