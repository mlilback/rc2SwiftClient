//
//  LivePreviewController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/29/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import WebKit
import ClientCore
import ReactiveSwift
import Down

protocol LivePreviewOutputHandler {
	var webView: WKWebView { get }
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController {
	var contextualMenuDelegate: ContextualMenuDelegate?
	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil) { didSet { contextChanged() }}
	private var contextDisposable: Disposable? = nil
	private var contentsDisposable: Disposable? = nil
	
	@IBOutlet weak var outputView: WKWebView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		outputView.loadHTMLString("Some <i>text</i> here\n<br>Just to see\n", baseURL: nil)
	}
	
	private func contextChanged() {
		contentsDisposable?.dispose()
		contentsDisposable = nil
		contextDisposable?.dispose()
		contextDisposable = context.signal.observeResult { [weak self] result in
			guard let me = self else { return }
			me.parseContent()
		}
		contentsDisposable = context.value?.currentDocument.value?.editedContents.signal.observeValues { [weak self] _ in
			guard let me = self else { return }
			me.parseContent()
		}
	}
	
	private func parseContent() {
		guard let newText = context.value?.currentDocument.value?.currentContents else {
			outputView.loadHTMLString("", baseURL: nil)
			return
		}
		// TODO: send file directory as baseURL
		outputView.loadHTMLString(newText, baseURL: nil)
	}
}
