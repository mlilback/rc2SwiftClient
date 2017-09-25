//
//  WebKitOutputController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import WebKit
import os
import ClientCore
import Networking
import ReactiveSwift
import Result

class WebKitOutputController: WebViewController {
	private var loadDisposable: Disposable?
	private var file: AppFile?
	private var restoredFileId: Int?
	
	override var pageTitle: String { return file?.name ?? "" }

	func saveSessionState() -> JSON {
		if let file = file {
			return .dictionary(["fileId": .int(file.fileId)])
		}
		return .dictionary([String: JSON]())
	}
	
	func restoreSessionState(_ state: JSON) {
		guard let fileId = try? state.getInt(at: "fileId") else { return }
		restoredFileId = fileId
		restoreLastFile()
	}
	
	override func sessionChanged() {
		restoreLastFile()
	}

	private func restoreLastFile() {
		guard let fileId = restoredFileId else { return }
		guard let file = session.workspace.file(withId: fileId) else { return }
		self.restoredFileId = nil
		session.fileCache.validUrl(for: file).start(on: UIScheduler()).startWithCompleted {
			self.load(file: file)
		}
	}
	
	///removes displayed contents
	func clearContents() {
		loadDisposable?.dispose()
		loadDisposable = nil
		_ = webView?.load(URLRequest(url: URL(string: "about:blank")!))
		file = nil
		titleLabel?.stringValue = ""
	}
	
	/// Loads the specified file, downloading if not cached
	///
	/// - Parameter file: file to display
	func load(file: AppFile) {
		loadLocalFile(session.fileCache.validUrl(for: file).start(on: UIScheduler()))
		self.file = file
		restoredFileId = nil
		titleLabel?.stringValue = file.name
	}
	
	/// loads the URL returned via the producer. Will dispose of any load currently in process when called
	private func loadLocalFile(_ producer: SignalProducer<URL, Rc2Error>) {
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
	private func loadLocalFile(_ url: URL) {
		assert(url.isFileURL)
		guard webView != nil else {
			DispatchQueue.main.async { self.loadLocalFile(url) }
			return
		}
		//it is utterly rediculous that we have to load a new webview every time, but it wasn't loading the second request
		DispatchQueue.main.async {
//			self.setupWebView()
			DispatchQueue.main.async {
				_ = self.webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
			}
		}
	}
}
