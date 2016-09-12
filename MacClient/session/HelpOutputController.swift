//
//  HelpOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit

open class HelpOutputController: WebViewController {
	override open func viewDidLoad() {
		super.viewDidLoad()
	}
	
	func loadHelpTopic(_ topic:HelpTopic) {
		let url = HelpController.sharedInstance.urlForTopic(topic)
		_ = webView?.load(URLRequest(url: url))
	}
	
	open func webView(_ webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void)
	{
		if let response = navigationResponse.response as? HTTPURLResponse {
			if response.statusCode == 404 {
				DispatchQueue.main.async {
					let furl = self.staticHmtlFolder()
					let purl = furl.appendingPathComponent("help404.html")
					_ = self.webView?.loadFileURL(purl, allowingReadAccessTo: furl as URL)
				}
				decisionHandler(.cancel)
			}
		}
		decisionHandler(.allow)
	}
	
}
