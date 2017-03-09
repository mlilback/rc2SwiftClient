//
//  OnboardingViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import WebKit
import os
import ClientCore
import Networking
import Freddy
import ReactiveSwift

class OnboardingViewController: NSViewController {
	@IBOutlet var openButton: NSButton!
	@IBOutlet var newButton: NSButton!
	@IBOutlet var webView: WKWebView!
	var conInfo: ConnectionInfo? { didSet {
		workspaceToken?.dispose()
		project = conInfo?.defaultProject
		workspaceToken = project?.workspaceChangeSignal.observe { [weak self] _ in
			self?.updateWorkspaces()
		}
	} }
	fileprivate var workspaceToken: Disposable?
	fileprivate var project: Project? { didSet {
		print("setting project")
	} }
	fileprivate var didFirstInit: Bool = false
	var openLocalWorkspace: ((WorkspaceIdentifier?) -> Void)?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		if !didFirstInit {
			didFirstInit = true
			self.view.layer?.backgroundColor = NSColor.white.cgColor
			webView.configuration.userContentController.add(self, name: "buttonClicked")
		}
		guard let welcomeUrl = Bundle.main.url(forResource: "welcome", withExtension: "html", subdirectory: "static_html") else
		{
			fatalError("failed to find welcome page")
		}
		webView.loadFileURL(welcomeUrl, allowingReadAccessTo: welcomeUrl.deletingLastPathComponent())
		view.window?.makeFirstResponder(webView)
	}
	
	func updateWorkspaces() {
		guard let project = project else { os_log("onboarding loaded w/o project"); return }
		let jsonStr = try! project.workspaces.sorted(by: { $0.name < $1.name } ).toJSON().serialize().base64EncodedString()
		webView.evaluateJavaScript("setWorkspaces('\(jsonStr)')")
	}
}

extension OnboardingViewController: WKNavigationDelegate {
	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
	{
		if navigationAction.request.url?.isFileURL ?? false {
			decisionHandler(.allow)
		} else {
			decisionHandler(.cancel)
		}
	}
	
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		updateWorkspaces()
	}
}

extension OnboardingViewController: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
	{
		guard let args = message.body as? Dictionary<String, Any>, let action = args["action"] as? String else {
			return
		}
		switch action {
		case "close":
			view.window?.orderOut(self)
		case "new":
			openLocalWorkspace?(nil)
			break
		case "open":
			guard let projId = project?.projectId, let wspaceId = args["wspaceId"] as? Double else {
				os_log("invalid params to open a session", log: .app, type: .error)
				return
			}
			openLocalWorkspace?(WorkspaceIdentifier(projectId: projId, wspaceId: Int(wspaceId)))
		default:
			os_log("unhandled action: %{public}s", log: .app, action)
		}
	}
}

class OnboardingWindowController: NSWindowController {
	var viewController: OnboardingViewController { return contentViewController as! OnboardingViewController }
}
