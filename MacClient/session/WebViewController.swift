//
//  WebViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit

class WebViewController: NSViewController, WKNavigationDelegate {
	var webView:WKWebView?
	@IBOutlet var containerView: NSView?
	@IBOutlet var navButtons: NSSegmentedControl?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var titleLabel: NSTextField?
	var webConfig: WKWebViewConfiguration?
	
	override func viewDidLoad() {
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
	}
	
	func setupWebView() {
		webView?.removeFromSuperview()
		webView = WKWebView(frame: CGRectInset(view.frame, 4, 4), configuration: webConfig!)
		webView?.navigationDelegate = self
		webView?.translatesAutoresizingMaskIntoConstraints = false
		containerView?.addSubview(webView!)
		webView!.topAnchor.constraintEqualToAnchor(containerView?.topAnchor).active = true
		webView!.bottomAnchor.constraintEqualToAnchor(containerView?.bottomAnchor).active = true
		webView!.leadingAnchor.constraintEqualToAnchor(containerView?.leadingAnchor).active = true
		webView!.trailingAnchor.constraintEqualToAnchor(containerView?.trailingAnchor).active = true
	}
	
	@IBAction func navigateWebView(sender:AnyObject) {
		switch ((navButtons?.selectedSegment)!) {
		case 0:
			webView?.goBack(sender)
		case 1:
			webView?.goForward(sender)
		default:
			break
		}
	}
	
	@IBAction func showShareSheet(sender:AnyObject) {
		let sharepicker = NSSharingServicePicker(items: [webView!.URL!])
		sharepicker.showRelativeToRect((shareButton?.frame)!, ofView: (shareButton?.superview)!, preferredEdge: .MaxY)
	}
	
	//MARK -- WKNavigationDelegate
	
	func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!)
	{
		navButtons?.setEnabled(webView.canGoBack, forSegment: 0)
		navButtons?.setEnabled(webView.canGoForward, forSegment: 1)
		titleLabel?.stringValue = webView.title!
	}
	
	func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
		log.warning("failed to navigate:\(error)")
	}
	
	func webView(webView: WKWebView, didCommitNavigation navigation: WKNavigation!) {
	}
}
