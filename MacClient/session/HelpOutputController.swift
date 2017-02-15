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
	
	override func currentPageSearchable() -> Bool {
		return webView?.url != nil
	}
	
	func loadHelpTopic(_ topic: HelpTopic) {
		let url = HelpController.shared.urlForTopic(topic)
		DispatchQueue.main.async {
			_ = self.webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
		}
	}
	
	open func webView(_ webView: WKWebView?, handleNavigation navigationResponse: WKNavigationResponse) -> Bool
	{
		if let response = navigationResponse.response as? HTTPURLResponse {
			if response.statusCode == 404 {
				DispatchQueue.main.async {
					let furl = self.staticHmtlFolder()
					let purl = furl.appendingPathComponent("help404.html")
					_ = self.webView?.loadFileURL(purl, allowingReadAccessTo: furl as URL)
				}
				return false
			}
		}
		return true
	}
	
}
