//
//  WebKitOutputController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import WebKit

class WebKitOutputController: WebViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
	}

	func clearContents() {
		webView?.loadRequest(NSURLRequest(URL: NSURL(string: "about:blank")!));
	}
	
	func loadLocalFile(url:NSURL) {
		guard webView !=  nil else {
			dispatch_async(dispatch_get_main_queue()) { self.loadLocalFile(url) }
			return
		}
		//it is utterly rediculous that we have to load a new webview every time, but it wasn't loading the second request
		setupWebView()
		webView?.loadFileURL(url, allowingReadAccessToURL: url.URLByDeletingLastPathComponent!)
	}
}
