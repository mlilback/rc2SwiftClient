//
//  OutputTabController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class OutputTabController: NSTabViewController, OutputHandler, ToolbarItemHandler {
	var consoleController: SessionOutputController?
	var imageController: ImageOutputController?
	var imageCache: ImageCache?
	var consoleToolbarControl: NSSegmentedControl?
	
	override func awakeFromNib() {
		super.awakeFromNib()
//		if consoleController != nil {
//			let titem = tabViewItemForViewController(consoleController!)!
//			titem.initialFirstResponder = consoleController?.consoleTextField
//		}
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		selectedTabViewItemIndex = 0
		consoleController = firstChildViewController(self)
		consoleController?.viewFileOrImage = displayFileOrImage
		imageController = firstChildViewController(self)
		imageController?.imageCache = imageCache
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
			consoleToolbarControl?.action = "consoleButtonClicked:"
			if let myItem = item as? OutputConsoleToolbarItem {
				myItem.tabController = self
			}
			return true
		} else if item.itemIdentifier == "clear" {
			item.target = self
			item.action = "clearConsole:"
			if let myItem = item as? ClearConsoleToolbarItem {
				myItem.textView = consoleController?.resultsView
				myItem.tabController = self
				
			}
			return true
		}
		return false
	}

	func clearConsole(sender:AnyObject?) {
		consoleController?.clearConsole(sender)
		imageCache?.clearCache()
	}
	
	func consoleButtonClicked(sender:AnyObject?) {
		selectedTabViewItemIndex = 0
	}
	
	func displayFileOrImage(fileWrapper: NSFileWrapper) {
		log.info("told to display file \(fileWrapper.filename)")
		if fileWrapper.filename?.hasPrefix("img") != nil,
			let fdata = fileWrapper.regularFileContents,
			let targetImg = NSKeyedUnarchiver.unarchiveObjectWithData(fdata) as? SessionImage,
			let images = imageCache?.sessionImagesForBatch(targetImg.batchId),
			let index = images.indexOf({$0.id == targetImg.id})
		{
			imageController?.displayImageAtIndex(index, images:images)
			selectedTabViewItemIndex = 1
			tabView.window?.toolbar?.validateVisibleItems()
		}
	}

	func appendFormattedString(string:NSAttributedString) {
		consoleController?.appendFormattedString(string)
		//switch back to console view
		if selectedTabViewItemIndex != 0 {
			selectedTabViewItemIndex = 0
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
