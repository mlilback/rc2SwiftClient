//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import os
import Networking

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

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	var consoleController: SessionOutputController?
	var imageController: ImageOutputController?
	var webController: WebKitOutputController?
	var helpController: HelpOutputController?
	var imageCache: ImageCache?
	weak var sessionController: SessionController?
	var consoleToolbarControl: NSSegmentedControl?
	var segmentItem: NSToolbarItem?
	var segmentControl: NSSegmentedControl?
	var displayedFileId: Int?
	var selectedOutputTab:OutputTabType {
		get { return OutputTabType(rawValue: selectedTabViewItemIndex)! }
		set { selectedTabViewItemIndex = newValue.rawValue ; adjustOutputTabSwitcher() }
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(OutputTabController.handleDisplayHelp(_:)), name: NSNotification.Name(rawValue: Notifications.DisplayHelpTopic), object: nil)
	}
	override func viewWillAppear() {
		super.viewWillAppear()
		selectedOutputTab = .console
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = displayFileAttachment
		imageController = firstChildViewController(self)
		imageController?.imageCache = imageCache
		webController = firstChildViewController(self)
		helpController = firstChildViewController(self)
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
			consoleController?.appendFormattedString(sessionController!.formatErrorMessage("No help found"))
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
			showHelp(HelpController.sharedInstance.topicsWithName(topicName))
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
	
	func displayFileAttachment(_ fileWrapper: FileWrapper) {
		os_log("told to display file %{public}s", log: .app, type:.info, fileWrapper.filename!)
		guard let attachment = try? MacConsoleAttachment.from(data: fileWrapper.regularFileContents!) else {
			os_log("asked to display invalid attachment", log: .app)
			return
		}
		switch (attachment.type) {
			case .file:
				if let file = sessionController?.session.workspace.file(withId: (Int(attachment.fileId))) {
					webController?.loadLocalFile(sessionController!.session.fileCache.cachedUrl(file:file))
					selectedOutputTab = .webKit
					//TODO: implement option to check by filename if not found by id
				} else {
					//TODO: report error
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
	
	func showFile(_ fileId:Int) {
		displayedFileId = fileId
		if let file = sessionController?.session.workspace.file(withId: fileId) {
			//TODO: need to specially handle images
			delay(0.5) { //delay is to give previous async file save time to actually write file to disk.
				self.webController?.loadLocalFile(self.sessionController!.session.fileCache.cachedUrl(file: file))
				self.selectedOutputTab = .webKit
			}
		} else {
			webController?.clearContents()
			selectedOutputTab = .console
		}
	}

	func appendFormattedString(_ string:NSAttributedString, type:OutputStringType = .default) {
		consoleController?.appendFormattedString(string, type:type)
		//switch back to console view
		if selectedOutputTab != .console {
			selectedOutputTab = .console
		}
	}

	func prepareForSearch() {
		consoleController?.performTextFinderAction(self)
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
	func adjustOutputTabSwitcher() {
		let index = selectedOutputTab.rawValue
		//		guard index != selectedTabViewItemIndex else { return }
		segmentControl?.animator().setSelected(true, forSegment: index)
		for idx in 0..<3 {
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
