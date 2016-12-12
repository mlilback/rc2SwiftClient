//
//  WebKitOutputController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import WebKit
import os
import ClientCore
import ReactiveSwift
import Result

class WebKitOutputController: WebViewController {
	private var loadDisposable: Disposable?
	
	///removes displayed contents
	func clearContents() {
		loadDisposable?.dispose()
		loadDisposable = nil
		_ = webView?.load(URLRequest(url: URL(string: "about:blank")!));
	}
	
	/// loads the URL returned via the producer. Will dispose of any load currently in process when called
	func loadLocalFile(_ producer: SignalProducer<URL, Rc2Error>) {
		loadDisposable?.dispose()
		loadDisposable = producer.startWithResult { result in
			guard let url = result.value else {
				os_log("failed to load file for viewing: %{public}@", log: .app, result.error!.localizedDescription)
				return
			}
			self.loadLocalFile(url)
		}
	}

	///displays the file in our webview
	/// - Parameter url: the file to load. Must be on the local file system.
	func loadLocalFile(_ url: URL) {
		assert(url.isFileURL)
		guard webView !=  nil else {
			DispatchQueue.main.async { self.loadLocalFile(url) }
			return
		}
		//it is utterly rediculous that we have to load a new webview every time, but it wasn't loading the second request
		DispatchQueue.main.async {
			self.setupWebView()
			_ = self.webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
		}
	}
}
