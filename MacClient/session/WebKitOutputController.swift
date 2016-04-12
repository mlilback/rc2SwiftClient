//
//  WebKitOutputController.swift
//  SwiftClient
//
//  Created by Mark Lilback on 4/11/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import Cocoa
import WebKit

class WebKitOutputController: NSViewController, WKNavigationDelegate {
	var webView:WKWebView?
	@IBOutlet var containerView: NSView?
	@IBOutlet var navButtons: NSSegmentedControl?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var titleLabel: NSTextField?
	
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
		webView = WKWebView(frame: CGRectInset(view.frame, 4, 4), configuration: config)
		webView?.navigationDelegate = self
		webView?.translatesAutoresizingMaskIntoConstraints = false
		containerView?.addSubview(webView!)
		webView!.topAnchor.constraintEqualToAnchor(containerView?.topAnchor).active = true
		webView!.bottomAnchor.constraintEqualToAnchor(containerView?.bottomAnchor).active = true
		webView!.leadingAnchor.constraintEqualToAnchor(containerView?.leadingAnchor).active = true
		webView!.trailingAnchor.constraintEqualToAnchor(containerView?.trailingAnchor).active = true
		webView!.widthAnchor.constraintEqualToAnchor(containerView?.widthAnchor).active = true
		webView!.heightAnchor.constraintEqualToAnchor(view.heightAnchor).active = true
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
		sharepicker.showRelativeToRect((shareButton?.frame)!, ofView: (shareButton?.superview)!, preferredEdge: .MinY)
	}
	
	func loadLocalFile(url:NSURL) {
		webView?.loadFileURL(url, allowingReadAccessToURL: url)
		
	}
	
	//MARK -- WKNavigationDelegate
	
	func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!)
	{
		navButtons?.setEnabled(webView.canGoBack, forSegment: 0)
		navButtons?.setEnabled(webView.canGoForward, forSegment: 1)
		titleLabel?.stringValue = webView.title!
	}
}
