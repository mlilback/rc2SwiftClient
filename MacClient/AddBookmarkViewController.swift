//
//  AddBookmarkViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class AddBookmarkViewController: NSViewController {
	@IBOutlet var continueButton:NSButton?
	@IBOutlet var containerView: NSView?
	var tabViewController:NSTabViewController?
	var selectServerController: SelectServerViewController?
	var projectManagerController: ProjectManagerViewController?
	var bookmarkManager:BookmarkManager?
	private var selectedServer: ServerHost?
	var bookmarkAddedClosure:((ServerHost, ProjectAndWorkspace) -> Void)?
	private var selectServerKVO:PMKVObserver?
	private var projectKVO:PMKVObserver?
	
	dynamic var isBusy:Bool = false
	dynamic var canContinue:Bool = false
	
	override func viewDidLoad() {
		super.viewDidLoad()
		tabViewController = self.storyboard?.instantiateControllerWithIdentifier("bookmarkTabController") as? NSTabViewController
		addChildViewController(tabViewController!)
		containerView?.addSubview(tabViewController!.view)
		tabViewController?.view.topAnchor.constraintEqualToAnchor(containerView?.topAnchor)
		tabViewController?.view.bottomAnchor.constraintEqualToAnchor(containerView!.bottomAnchor)
		tabViewController?.view.leftAnchor.constraintEqualToAnchor(containerView!.leftAnchor)
		tabViewController?.view.rightAnchor.constraintEqualToAnchor(containerView!.rightAnchor)
		selectServerController = firstChildViewController(self)
		projectManagerController = firstChildViewController(self)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.view.window?.preventsApplicationTerminationWhenModal = false
		selectServerKVO = KVObserver(object: selectServerController!, keyPath:"canContinue", options: [.Initial])
		{ (object, _, _) in
			self.adjustCanContinue(object as SelectServerViewController)
		}
		projectKVO =  KVObserver(object: projectManagerController!, keyPath:"canContinue", options: [])
		{ (object, _, _) in
			self.adjustCanContinue(object as ProjectManagerViewController)
		}
	}
	
	func adjustCanContinue<T where T:NSViewController, T:EmbeddedDialogController>(controller:T) {
		if controller == tabViewController?.currentTabItemViewController {
			canContinue = controller.canContinue
		}
	}

	override func viewDidDisappear() {
		super.viewDidDisappear()
		selectServerKVO?.cancel()
		projectKVO?.cancel()
	}

	func displayError(error:NSError) {
		log.error("got error: \(error)")
	}
	
	func switchToProjectManager(serverInfo:SelectServerResponse) {
		tabViewController?.selectedTabViewItemIndex = 1
		projectManagerController!.host = serverInfo.server
		projectManagerController!.loginSession = serverInfo.loginSession
		canContinue = projectManagerController!.canContinue
	}
	
	@IBAction func continueAction(sender:AnyObject?) {
		if selectServerController == tabViewController?.currentTabItemViewController {
			selectServerController!.continueAction() { (value, error) in
				guard error == nil else {
					self.displayError(error!)
					return
				}
				let serverResponse = value as! SelectServerResponse
				self.selectedServer = serverResponse.server
				self.switchToProjectManager(serverResponse)
			}
		} else if projectManagerController == tabViewController?.currentTabItemViewController {
			projectManagerController!.continueAction() { (value, error) in
				guard error == nil else { self.displayError(error!); return }
				
				self.bookmarkAddedClosure?(self.selectedServer!, value as! ProjectAndWorkspace)
			}
		}
	}
	
	@IBAction func cancelAction(sender:AnyObject?) {
		self.presentingViewController?.dismissViewController(self)
	}
}
