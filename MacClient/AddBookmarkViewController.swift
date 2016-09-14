//
//  AddBookmarkViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os

class AddBookmarkViewController: NSViewController {
	@IBOutlet var continueButton:NSButton?
	@IBOutlet var containerView: NSView?
	var tabViewController:NSTabViewController?
	var selectServerController: SelectServerViewController?
	var projectManagerController: ProjectManagerViewController?
	var bookmarkManager:BookmarkManager?
	fileprivate var selectedServer: ServerHost?
	var bookmarkAddedClosure:((ServerHost, ProjectAndWorkspace) -> Void)?
	fileprivate var selectServerKVO:PMKVObserver?
	fileprivate var projectKVO:PMKVObserver?
	
	dynamic var isBusy:Bool = false
	dynamic var canContinue:Bool = false
	
	override func viewDidLoad() {
		super.viewDidLoad()
		tabViewController = self.storyboard?.instantiateController(withIdentifier: "bookmarkTabController") as? NSTabViewController
		addChildViewController(tabViewController!)
		containerView?.addSubview(tabViewController!.view)
		tabViewController?.view.topAnchor.constraint(equalTo: (containerView?.topAnchor)!)
		tabViewController?.view.bottomAnchor.constraint(equalTo: containerView!.bottomAnchor)
		tabViewController?.view.leftAnchor.constraint(equalTo: containerView!.leftAnchor)
		tabViewController?.view.rightAnchor.constraint(equalTo: containerView!.rightAnchor)
		selectServerController = firstChildViewController(self)
		projectManagerController = firstChildViewController(self)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.view.window?.preventsApplicationTerminationWhenModal = false
		selectServerKVO = KVObserver(object: selectServerController!, keyPath:"canContinue", options: [.initial])
		{ (object, _, _) in
			self.adjustCanContinue(object as SelectServerViewController)
		}
		projectKVO =  KVObserver(object: projectManagerController!, keyPath:"canContinue", options: [])
		{ (object, _, _) in
			self.adjustCanContinue(object as ProjectManagerViewController)
		}
	}
	
	func adjustCanContinue<T>(_ controller:T) where T:NSViewController, T:EmbeddedDialogController {
		if controller == tabViewController?.currentTabItemViewController {
			canContinue = controller.canContinue
		}
	}

	override func viewDidDisappear() {
		super.viewDidDisappear()
		selectServerKVO?.cancel()
		projectKVO?.cancel()
	}

	func displayError(_ error:NSError) {
		os_log("error: %{public}@", type:.error, error)
	}
	
	func switchToProjectManager(_ serverInfo:SelectServerResponse) {
		tabViewController?.selectedTabViewItemIndex = 1
		projectManagerController!.host = serverInfo.server
		projectManagerController!.loginSession = serverInfo.loginSession
		canContinue = projectManagerController!.canContinue
	}
	
	@IBAction func continueAction(_ sender:AnyObject?) {
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
	
	@IBAction func cancelAction(_ sender:AnyObject?) {
		self.presenting?.dismissViewController(self)
	}
}
