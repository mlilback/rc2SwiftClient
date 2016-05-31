//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

enum OutputTabType: Int {
	 case Console = 0, Image, WebKit, Help
}

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	var consoleController: SessionOutputController?
	var imageController: ImageOutputController?
	var webController: WebKitOutputController?
	var helpController: HelpOutputController?
	var imageCache: ImageCache?
	var session: Session?
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
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(OutputTabController.showHelp(_:)), name: DisplayHelpTopicNotification, object: nil)
	}
	override func viewWillAppear() {
		super.viewWillAppear()
		selectedOutputTab = .Console
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
	
	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
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
	
	dynamic func tabSwitcherClicked(sender:AnyObject?) {
		let index = (segmentControl?.selectedSegment)!
		selectedOutputTab = OutputTabType(rawValue: index)!
//		NSUserDefaults.standardUserDefaults().setInteger(index, forKey: LastSelectedSessionTabIndex)
	}

	func adjustOutputTabSwitcher() {
		let index = selectedOutputTab.rawValue
//		guard index != selectedTabViewItemIndex else { return }
		segmentControl?.animator().setSelected(true, forSegment: index)
		for idx in 0..<3 {
			[segmentControl?.setEnabled(idx == index ? false : true, forSegment: idx)]
		}
	}
	
	func showHelp(note:NSNotification) {
		var url:NSURL?
		if let topic:HelpTopic = note.object as? HelpTopic {
			url = HelpController.sharedInstance.urlForTopic(topic)
		} else if let topicName:String = note.object as? String {
			let topics = HelpController.sharedInstance.topicsWithName(topicName)
			if topics.count > 0 {
				//TODO: handle if more than one matching help target
				url = HelpController.sharedInstance.urlForTopic(topics[0].subtopics![0])
			}
		} else {
			selectedOutputTab = .Console
		}
		if url != nil {
			selectedOutputTab = .Help
			helpController?.loadUrl(url!)
		}
	}

	func clearConsole(sender:AnyObject?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
	}
	
	func consoleButtonClicked(sender:AnyObject?) {
		selectedOutputTab = .Console
	}
	
	func displayFileAttachment(fileWrapper: NSFileWrapper) {
		log.info("told to display file \(fileWrapper.filename)")
		guard let attachment = NSKeyedUnarchiver.unarchiveObjectWithData(fileWrapper.regularFileContents!) as? MacConsoleAttachment else {
			log.warning("asked to display invalid attachment")
			return
		}
		switch (attachment.type) {
			case .File:
				if let file = session?.workspace.fileWithId(Int(attachment.fileId)) {
					webController?.loadLocalFile(session!.fileHandler.fileCache.cachedFileUrl(file))
					selectedOutputTab = .WebKit
					//TODO: implement option to check by filename if not found by id
				} else {
					//TODO: report error
				}
			case .Image:
				if let image = attachment.image,
				let images = imageCache?.sessionImagesForBatch(image.batchId),
				let index = images.indexOf({$0.id == image.id})
			{
				imageController?.displayImageAtIndex(index, images:images)
				selectedOutputTab = .Image
				tabView.window?.toolbar?.validateVisibleItems()
			}
		}
	}
	
	func showFile(fileId:Int) {
		displayedFileId = fileId
		if let file = session?.workspace.fileWithId(fileId) {
			//TODO: need to specially handle images
			delay(0.5) { //delay is to give previous async file save time to actually write file to disk.
				self.webController?.loadLocalFile(self.session!.fileHandler.fileCache.cachedFileUrl(file))
				self.selectedOutputTab = .WebKit
			}
		} else {
			webController?.clearContents()
			selectedOutputTab = .Console
		}
	}

	func appendFormattedString(string:NSAttributedString, type:OutputStringType = .Default) {
		consoleController?.appendFormattedString(string, type:type)
		//switch back to console view
		if selectedOutputTab != .Console {
			selectedOutputTab = .Console
		}
	}

	func prepareForSearch() {
		consoleController?.performTextFinderAction(self)
	}
	
	func saveSessionState() -> AnyObject {
		var dict = [String:AnyObject]()
		dict["console"] = consoleController?.saveSessionState()
		return dict
	}
	
	func restoreSessionState(state:[String:AnyObject]) {
		if let consoleState = state["console"] as? [String:AnyObject] {
			consoleController?.restoreSessionState(consoleState)
		}
	}
}

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
		enabled = textView?.textStorage?.length > 0 && tabController?.selectedTabViewItemIndex == 0
	}
}

class OutputConsoleToolbarItem : NSToolbarItem {
	weak var tabController: NSTabViewController?
	override func validate() {
		enabled = tabController?.selectedTabViewItemIndex > 0
	}
}
