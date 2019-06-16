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

protocol LivePreviewOutputController {
	/// might not need to be accessible
//	var webView: WKWebView { get }
	/// 
//	var sessionController: SessionController? { get set }
	/// alows preview editor to tell display controller what the current context is so it can monitor the current document
	var editorContext: EditorContext? { get set }
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController {
	var contextualMenuDelegate: ContextualMenuDelegate?
	var sessionController: SessionController?
	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil) { didSet { contextChanged() }}
	private var contextDisposable: Disposable? = nil
	private var contentsDisposable: Disposable? = nil
	
	var editorContext: EditorContext? {
		get { return context.value }
		set { context.value = newValue }
	}
	
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
