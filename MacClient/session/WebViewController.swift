//
//  WebViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit
import os

open class WebViewController: NSViewController, WKNavigationDelegate {
	var webView:WKWebView?
	@IBOutlet var containerView: NSView?
	@IBOutlet var navButtons: NSSegmentedControl?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var titleLabel: NSTextField?
	var webConfig: WKWebViewConfiguration?
	
	override open func viewDidLoad() {
		super.viewDidLoad()
		let prefs = WKPreferences()
		prefs.minimumFontSize = 9.0;
		prefs.javaEnabled = false
		prefs.javaScriptCanOpenWindowsAutomatically = false
		let config = WKWebViewConfiguration()
		config.preferences = prefs
		config.applicationNameForUserAgent = "Rc2"
		config.allowsAirPlayForMediaPlayback = true
		webConfig = config
		setupWebView()
		titleLabel?.stringValue = ""
	}
	
	func setupWebView() {
		webView?.removeFromSuperview()
		webView = WKWebView(frame: view.frame.insetBy(dx: 4, dy: 4), configuration: webConfig!)
		webView?.navigationDelegate = self
		webView?.translatesAutoresizingMaskIntoConstraints = false
		containerView?.addSubview(webView!)
		webView!.topAnchor.constraint(equalTo: (containerView?.topAnchor)!).isActive = true
		webView!.bottomAnchor.constraint(equalTo: (containerView?.bottomAnchor)!).isActive = true
		webView!.leadingAnchor.constraint(equalTo: (containerView?.leadingAnchor)!).isActive = true
		webView!.trailingAnchor.constraint(equalTo: (containerView?.trailingAnchor)!).isActive = true
	}
	
	@IBAction func navigateWebView(_ sender:AnyObject) {
		switch ((navButtons?.selectedSegment)!) {
		case 0:
			webView?.goBack(sender)
		case 1:
			webView?.goForward(sender)
		default:
			break
		}
	}
	
	@IBAction func showShareSheet(_ sender:AnyObject) {
		let sharepicker = NSSharingServicePicker(items: [webView!.url!])
		sharepicker.show(relativeTo: (shareButton?.frame)!, of: (shareButton?.superview)!, preferredEdge: .maxY)
	}

	func staticHmtlFolder() -> URL {
		let pkg = Bundle(for: type(of: self))
		let url = pkg.url(forResource: "help404", withExtension: "html", subdirectory: "static_html")
		return url!.deletingLastPathComponent()
	}

	//MARK -- WKNavigationDelegate
	
	open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
	{
		navButtons?.setEnabled(webView.canGoBack, forSegment: 0)
		navButtons?.setEnabled(webView.canGoForward, forSegment: 1)
		titleLabel?.stringValue = webView.title!
	}
	
	open func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		os_log("failed to navigate:%{public}s", type:.error, error as NSError)
	}
	
	open func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
	}
}
