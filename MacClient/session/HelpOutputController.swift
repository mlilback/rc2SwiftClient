//
//  HelpOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit

public class HelpOutputController: WebViewController {
	override public func viewDidLoad() {
		super.viewDidLoad()
	}
	
	func loadHelpTopic(topic:HelpTopic) {
		let url = HelpController.sharedInstance.urlForTopic(topic)
		webView?.loadRequest(NSURLRequest(URL: url))
	}
	
	public func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void)
	{
		if let response = navigationResponse.response as? NSHTTPURLResponse {
			if response.statusCode == 404 {
				dispatch_async(dispatch_get_main_queue()) {
					let furl = self.staticHmtlFolder()
					let purl = furl.URLByAppendingPathComponent("help404.html")
					self.webView?.loadFileURL(purl!, allowingReadAccessToURL: furl)
				}
				decisionHandler(.Cancel)
			}
		}
		decisionHandler(.Allow)
	}
	
}
