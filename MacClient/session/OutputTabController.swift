//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import os
import Freddy
import Networking
import ReactiveSwift
import ReactiveCocoa
import Result
import SwiftyUserDefaults

enum OutputTab: Int {
	 case console = 0, image, webKit, help
}

protocol OutputController: Searchable {
	var searchBarVisible: Bool { get }
}

extension OutputController {
	var searchBarVisible: Bool { return false }
}

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	// MARK: properties
	var currentOutputController: OutputController!
	var consoleController: ConsoleOutputController?
	var imageController: ImageOutputController?
	var webController: WebKitOutputController?
	var helpController: HelpOutputController?
	var imageCache: ImageCache? { return sessionController?.session.imageCache }
	weak var sessionController: SessionController? { didSet { sessionControllerUpdated() } }
	weak var displayedFile: File?
	var searchBarVisible: Bool {
		get { return currentOutputController.searchBarVisible }
		set { currentOutputController.performFind(action: newValue ? .showFindInterface : .hideFindInterface) }
	}
	let selectedOutputTab = MutableProperty<OutputTab>(.console)
	fileprivate var restoredOutputTab: OutputTab = .console
	fileprivate var restoredSelectedImageId: Int = 0

	// MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(OutputTabController.handleDisplayHelp(_:)), name: .DisplayHelpTopic, object: nil)
		selectedOutputTab.signal.observeValues { [weak self] tab in
			self?.switchTo(tab: tab)
		}
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		guard consoleController == nil else { return }
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = displayAttachment
		imageController = firstChildViewController(self)
		imageController?.imageCache = imageCache
		webController = firstChildViewController(self)
		helpController = firstChildViewController(self)
		currentOutputController = consoleController
	}
	
	private func sessionControllerUpdated() {
		imageController?.imageCache = imageCache
		DispatchQueue.main.async {
			self.selectedOutputTab.value = self.restoredOutputTab
			self.imageController?.display(imageId: self.restoredSelectedImageId)
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
		if item.itemIdentifier == "clear" {
			item.target = self
			item.action = #selector(OutputTabController.clearConsole(_:))
			if let myItem = item as? ClearConsoleToolbarItem {
				myItem.textView = consoleController?.resultsView
				myItem.tabController = self
				
			}
			return true
		}
		return false
	}
	
	func showHelp(_ topics: [HelpTopic]) {
		guard topics.count > 0 else {
			consoleController?.append(responseString: sessionController!.format(errorString: "No help found"))
			return
		}
		if topics.count == 1 {
			showHelpTopic(topics[0])
			return
		}
		//TODO: handle prompt for selecting a topic out of topics
		showHelpTopic(topics[0])
	}
	
	func handleDisplayHelp(_ note: Notification) {
		if let topic: HelpTopic = note.object as? HelpTopic {
			showHelpTopic(topic)
		} else if let topicName: String = note.object as? String {
			showHelp(HelpController.shared.topicsWithName(topicName))
		} else { //told to show without a topic. switch back to console.
			selectedOutputTab.value = .console
		}
	}

	func clearConsole(_ sender: AnyObject?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
	}
	
	func displayAttachment(_ fileWrapper: FileWrapper) {
		os_log("told to display file %{public}@", log: .app, type:.info, fileWrapper.filename!)
		guard let attachment = try? MacConsoleAttachment.from(data: fileWrapper.regularFileContents!) else {
			os_log("asked to display invalid attachment", log: .app)
			return
		}
		switch attachment.type {
		case .file:
			if let file = sessionController?.session.workspace.file(withId: attachment.fileId) {
				webController?.loadLocalFile(sessionController!.session.fileCache.validUrl(for: file))
				selectedOutputTab.value = .webKit
			} else {
				//TODO: report error
				os_log("error getting file attachment to display: %d", log: .app, attachment.fileId)
			}
		case .image:
			if let image = attachment.image {
				imageController?.display(image: image)
				selectedOutputTab.value = .image
				tabView.window?.toolbar?.validateVisibleItems()
			}
		}
	}
	
	func showFile(_ fileObject: AnyObject?) {
		//strip optional
		guard let file = fileObject as? File else {
			webController?.clearContents()
			selectedOutputTab.value = .console
			displayedFile = nil
			return
		}
		let url = self.sessionController!.session.fileCache.cachedUrl(file: file)
		guard url.fileSize() > 0 else {
			//caching/download bug. not sure what causes it. recache the file and then call again
			sessionController?.session.fileCache.recache(file: file).observe(on: UIScheduler()).startWithCompleted {
				self.showFile(file)
			}
			return
		}
		displayedFile = file
		//TODO: need to specially handle images
		self.selectedOutputTab.value = .webKit
		self.webController?.loadLocalFile(url)
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

	func handleSearch(action: NSTextFinderAction) {
		currentOutputController.performFind(action: action)
	}
	
	func saveSessionState() -> JSON {
		var dict = [String: JSON]()
		dict["console"] = consoleController?.saveSessionState()
		dict["selTab"] = .int(selectedOutputTab.value.rawValue)
		dict["selImage"] = .int(imageController?.selectedImageId ?? 0)
		return .dictionary(dict)
	}
	
	func restoreSessionState(_ state: JSON) {
		if let consoleState = state["console"] {
			consoleController?.restoreSessionState(consoleState)
		}
		if let rawValue = try? state.getInt(at: "selTab"), let selTab = OutputTab(rawValue: rawValue) {
			restoredOutputTab = selTab
		}
		restoredSelectedImageId = state.getOptionalInt(at: "selImage") ?? 0
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
