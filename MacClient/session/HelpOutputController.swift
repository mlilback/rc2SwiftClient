//
//  HelpOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit

class HelpOutputController: WebViewController {
	override func viewDidLoad() {
		super.viewDidLoad()
	}
	
	func loadUrl(url:NSURL) {
		webView?.loadRequest(NSURLRequest(URL: url))
	}
}
