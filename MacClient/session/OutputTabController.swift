//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let ConsoleTabIndex = 0
let ImageTabIndex = 1
let WebKitTabIndex = 2
let HelpTabIndex = 3

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	var consoleController: SessionOutputController?
	var imageController: ImageOutputController?
	var webController: WebKitOutputController?
	var helpController: HelpOutputController?
	var imageCache: ImageCache?
	var session: Session?
	var consoleToolbarControl: NSSegmentedControl?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(OutputTabController.showHelp(_:)), name: DisplayHelpTopicNotification, object: nil)
	}
	override func viewWillAppear() {
		super.viewWillAppear()
		selectedTabViewItemIndex = ConsoleTabIndex
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = displayFileOrImage
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
		}
		return false
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
			if url != nil {
				selectedTabViewItemIndex = HelpTabIndex
				helpController?.loadUrl(url!)
			}
		} else {
			selectedTabViewItemIndex = ConsoleTabIndex
		}
	}

	func clearConsole(sender:AnyObject?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
	}
	
	func consoleButtonClicked(sender:AnyObject?) {
		selectedTabViewItemIndex = ConsoleTabIndex
	}
	
	func displayFileOrImage(fileWrapper: NSFileWrapper) {
		log.info("told to display file \(fileWrapper.filename)")
		guard let fname = fileWrapper.filename else { return }
		if  fname.hasPrefix("img"),
			let fdata = fileWrapper.regularFileContents,
			let targetImg = NSKeyedUnarchiver.unarchiveObjectWithData(fdata) as? SessionImage,
			let images = imageCache?.sessionImagesForBatch(targetImg.batchId),
			let index = images.indexOf({$0.id == targetImg.id})
		{
			imageController?.displayImageAtIndex(index, images:images)
			selectedTabViewItemIndex = ImageTabIndex
			tabView.window?.toolbar?.validateVisibleItems()
		} else if let fdata = fileWrapper.regularFileContents,
			let fdict = NSKeyedUnarchiver.unarchiveObjectWithData(fdata) as? NSDictionary,
			let fileId = fdict["id"] as? Int,
			let file = session?.workspace.fileWithId(fileId)
		{
			webController?.loadLocalFile(session!.fileHandler.fileCache.cachedFileUrl(file))
			selectedTabViewItemIndex = WebKitTabIndex
		}
	}

	func appendFormattedString(string:NSAttributedString, type:OutputStringType = .Default) {
		consoleController?.appendFormattedString(string, type:type)
		//switch back to console view
		if selectedTabViewItemIndex != ConsoleTabIndex {
			selectedTabViewItemIndex = ConsoleTabIndex
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
