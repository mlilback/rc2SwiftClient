//
//  OnboardingViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import WebKit
import MJLLogger
import ClientCore
import Networking
import Freddy
import ReactiveSwift
import Model

class OnboardingViewController: NSViewController {
	@IBOutlet var openButton: NSButton!
	@IBOutlet var newButton: NSButton!
	@IBOutlet var webView: WKWebView!
	var conInfo: ConnectionInfo? { didSet {
		workspaceToken?.dispose()
		project = conInfo?.defaultProject
		workspaceToken = project?.workspaces.signal.observe { [weak self] _ in
			self?.updateWorkspaces()
		}
	} }
	fileprivate var workspaceToken: Disposable?
	fileprivate var project: AppProject?
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
		guard
			let workspaces = project?.workspaces.value.map( { $0.model }).sorted(by: { (lhs, rhs) -> Bool in return lhs.name < rhs.name }),
			let rawData = try? conInfo?.encode(workspaces),
			let jsonData = rawData
		 else { Log.warn("onboarding loaded w/o project", .app); return }
		webView.evaluateJavaScript("setWorkspaces('\(jsonData.base64EncodedString())')")
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
		guard let args = message.body as? [String: Any], let action = args["action"] as? String else {
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
				Log.error("invalid params to open a session", .app)
				return
			}
			openLocalWorkspace?(WorkspaceIdentifier(projectId: projId, wspaceId: Int(wspaceId)))
		default:
			Log.info("unhandled action: \(action)", .app)
		}
	}
}

class OnboardingWindowController: NSWindowController {
	// swiftlint:disable:next force_cast
	var viewController: OnboardingViewController { return contentViewController as! OnboardingViewController }
}
