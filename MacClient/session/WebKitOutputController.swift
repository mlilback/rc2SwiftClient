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
		_ = webView?.load(URLRequest(url: URL(string: "about:blank")!));
	}
	
	func loadLocalFile(_ url:URL) {
		guard webView !=  nil else {
			DispatchQueue.main.async { self.loadLocalFile(url) }
			return
		}
		//it is utterly rediculous that we have to load a new webview every time, but it wasn't loading the second request
		setupWebView()
		_ = webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
	}
}
