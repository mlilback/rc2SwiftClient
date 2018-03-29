//
//  HelpOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit
import Networking
import ClientCore

class HelpOutputController: WebViewController {
	private var currentTopic: HelpTopic?
	
	override open func viewDidLoad() {
		super.viewDidLoad()
		if let topic = currentTopic {
			loadHelpTopic(topic)
		}
	}
	
	func save(state: inout SessionState.WebViewState) {
		if let topic = currentTopic, let tid = topic.topicId {
			state.contentsId = tid
		}
	}
	
	func restore(state: SessionState.WebViewState) {
		guard let topicId = state.contentsId else { return }
		currentTopic = HelpController.shared.topic(withId: topicId)
		if let topic = currentTopic {
			loadHelpTopic(topic)
		}
	}

	func loadHelpTopic(_ topic: HelpTopic) {
		currentTopic = topic
		let hcontroller = HelpController.shared
		let url = hcontroller.urlForTopic(topic)
		DispatchQueue.main.async {
			_ = self.webView?.loadFileURL(url, allowingReadAccessTo: hcontroller.baseHelpUrl)
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
