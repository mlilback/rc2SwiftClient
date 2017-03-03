//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import os
import Networking
import ReactiveSwift

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}

enum OutputTabType: Int {
	 case console = 0, image, webKit, help
}

protocol OutputController: Searchable {
	var searchBarVisible: Bool { get }
}

extension OutputController {
	var searchBarVisible: Bool { return false }
}

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	//MARK: properties
	var currentOutputController: OutputController!
	var consoleController: ConsoleOutputController?
	var imageController: ImageOutputController?
	var webController: WebKitOutputController?
	var helpController: HelpOutputController?
	var imageCache: ImageCache? { return sessionController?.session.imageCache }
	weak var sessionController: SessionController? { didSet { imageController?.imageCache = imageCache } }
	var consoleToolbarControl: NSSegmentedControl?
	var segmentItem: NSToolbarItem?
	var segmentControl: NSSegmentedControl?
	weak var displayedFile: File?
	var selectedOutputTab: OutputTabType {
		get { return OutputTabType(rawValue: selectedTabViewItemIndex)! }
		set { switchTo(tab: newValue) }
	}
	var searchBarVisible: Bool {
		get { return currentOutputController.searchBarVisible }
		set { currentOutputController.performFind(action: newValue ? .showFindInterface : .hideFindInterface) }
	}
	
	//MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(OutputTabController.handleDisplayHelp(_:)), name: .DisplayHelpTopic, object: nil)
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		selectedOutputTab = .console
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = displayAttachment
		imageController = firstChildViewController(self)
		imageController?.imageCache = imageCache
		webController = firstChildViewController(self)
		helpController = firstChildViewController(self)
		currentOutputController = consoleController
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
		if item.itemIdentifier == "console" {
			consoleToolbarControl = item.view as! NSSegmentedControl?
			consoleToolbarControl?.target = self
			consoleToolbarControl?.action = #selector(OutputTabController.consoleButtonClicked(_:))
			if let myItem = item as? OutputConsoleToolbarItem {
				myItem.tabController = self
			}
			return true
		} else if item.itemIdentifier == "clear" {
			item.target = self
			item.action = #selector(OutputTabController.clearConsole(_:))
			if let myItem = item as? ClearConsoleToolbarItem {
				myItem.textView = consoleController?.resultsView
				myItem.tabController = self
				
			}
			return true
		} else if item.itemIdentifier == "rightView" {
			segmentItem = item
			segmentControl = item.view as! NSSegmentedControl?
			segmentControl?.target = self
			segmentControl?.action = #selector(OutputTabController.tabSwitcherClicked(_:))
			let lastSelection = 0 //NSUserDefaults.standardUserDefaults().integerForKey(LastSelectedSessionTabIndex)
			selectedOutputTab = OutputTabType(rawValue: lastSelection)!
			return true
		}
		return false
	}
	
	dynamic func tabSwitcherClicked(_ sender:AnyObject?) {
		let index = (segmentControl?.selectedSegment)!
		selectedOutputTab = OutputTabType(rawValue: index)!
//		NSUserDefaults.standardUserDefaults().setInteger(index, forKey: LastSelectedSessionTabIndex)
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
	
	func handleDisplayHelp(_ note:Notification) {
		if let topic:HelpTopic = note.object as? HelpTopic {
			showHelpTopic(topic)
		} else if let topicName:String = note.object as? String {
			showHelp(HelpController.shared.topicsWithName(topicName))
		} else { //told to show without a topic. switch back to console.
			selectedOutputTab = .console
		}
	}

	func clearConsole(_ sender:AnyObject?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
	}
	
	func consoleButtonClicked(_ sender:AnyObject?) {
		selectedOutputTab = .console
	}
	
	func displayAttachment(_ fileWrapper: FileWrapper) {
		os_log("told to display file %{public}@", log: .app, type:.info, fileWrapper.filename!)
		guard let attachment = try? MacConsoleAttachment.from(data: fileWrapper.regularFileContents!) else {
			os_log("asked to display invalid attachment", log: .app)
			return
		}
		switch (attachment.type) {
			case .file:
				if let file = sessionController?.session.workspace.file(withId: attachment.fileId) {
					webController?.loadLocalFile(sessionController!.session.fileCache.validUrl(for: file))
					selectedOutputTab = .webKit
				} else {
					//TODO: report error
					os_log("error getting file attachment to display: %d", log: .app, attachment.fileId)
				}
			case .image:
				if let image = attachment.image,
				let images = imageCache?.sessionImages(forBatch: image.batchId),
				let index = images.index(where: {$0.id == image.id})
			{
				imageController?.displayImage(atIndex: index, images:images)
				selectedOutputTab = .image
				tabView.window?.toolbar?.validateVisibleItems()
			}
		}
	}
	
	func showFile(_ fileObject: AnyObject?) {
		//strip optional
		guard let file = fileObject as? File else {
			webController?.clearContents()
			selectedOutputTab = .console
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
		self.selectedOutputTab = .webKit
		self.webController?.loadLocalFile(url)
	}

	func append(responseString: ResponseString) {
		consoleController?.append(responseString: responseString)
		//switch back to console view if appropriate type
		switch responseString.type {
		case .input, .output, .error:
			if selectedOutputTab != .console {
				selectedOutputTab = .console
			}
		default:
			break
		}
	}

	func handleSearch(action: NSTextFinderAction) {
		currentOutputController.performFind(action: action)
	}
	
	func saveSessionState() -> AnyObject {
		var dict = [String:AnyObject]()
		dict["console"] = consoleController?.saveSessionState()
		return dict as AnyObject
	}
	
	func restoreSessionState(_ state:[String:AnyObject]) {
		if let consoleState = state["console"] as? [String:AnyObject] {
			consoleController?.restoreSessionState(consoleState)
		}
	}
}

//MARK: - private methods
private extension OutputTabController {
	func switchTo(tab: OutputTabType) {
		selectedTabViewItemIndex = tab.rawValue
		switch selectedOutputTab {
		case .console:
			currentOutputController = consoleController
		case .image:
			currentOutputController = imageController
		case .webKit:
			currentOutputController = webController
		case .help:
			currentOutputController = helpController
		}
		adjustOutputTabSwitcher()
	}
	
	func adjustOutputTabSwitcher() {
		let index = selectedOutputTab.rawValue
		//		guard index != selectedTabViewItemIndex else { return }
		segmentControl?.animator().setSelected(true, forSegment: index)
		for idx in 0..<tabView.numberOfTabViewItems {
			segmentControl?.setEnabled(idx == index ? false : true, forSegment: idx)
		}
	}
	
	///actually shows the help page for the specified topic
	func showHelpTopic(_ topic:HelpTopic) {
		selectedOutputTab = .help
		helpController!.loadHelpTopic(topic)
	}
}

//MARK: - helper classes
class OutputTopView : NSTabView {
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
		isEnabled = textView?.textStorage?.length > 0 && tabController?.selectedTabViewItemIndex == 0
	}
}

class OutputConsoleToolbarItem : NSToolbarItem {
	weak var tabController: NSTabViewController?
	override func validate() {
		isEnabled = tabController?.selectedTabViewItemIndex > 0
	}
}
