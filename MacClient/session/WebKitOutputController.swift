//
//  WebKitOutputController.swift
//  SwiftClient
//
//  Created by Mark Lilback on 4/11/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import Cocoa
import WebKit

class WebKitOutputController: WebViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
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
