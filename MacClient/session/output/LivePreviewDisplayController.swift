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
import SyntaxParsing
import ReactiveSwift
import Down

protocol LivePreviewOutputController {
	/// might not need to be accessible
//	var webView: WKWebView { get }
	/// 
//	var sessionController: SessionController? { get set }
	/// allows preview editor to tell display controller what the current context is so it can monitor the current document
	var editorContext: EditorContext? { get set }
	/// allows editor that the user has made a change to the contents of the current document
	///
	/// - Parameters:
	///   - range: the range of the text in the original string
	///   - delta: the change made
	/// - Returns: true if the changes should be saved to the current document's editedContents causing a reparse
	func contentsEdited(range: NSRange, delta: Int) -> Bool
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController {
	var contextualMenuDelegate: ContextualMenuDelegate?
	var sessionController: SessionController?
	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil) { didSet { contextChanged() }}
	private let contextDisposables = CompositeDisposable()
	private var contentsDisposable: Disposable?
	
	var editorContext: EditorContext? {
		get { return context.value }
		set {
			context.value = newValue
			contextChanged()
		}
	}
	
	@IBOutlet weak var outputView: WKWebView?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		do {
			guard let headerUrl = Bundle.main.url(forResource: "customRmdHeader", withExtension: "html"),
				let footerUrl = Bundle.main.url(forResource: "customRmdFooter", withExtension: "html")
			else {
				fatalError("failed to load live preview template file")
			}
			let header = try String(contentsOf: headerUrl)
			let footer = try String(contentsOf: footerUrl)
			outputView?.loadHTMLString("\(header) Body <span id\"foobar\">Goes</span> Here \(footer)", baseURL: nil)
		} catch {
			fatalError("failed to load live preview template file: \(error.localizedDescription)")
		}
	}
	
	/// called by the editor when the user has made an edit, resulting in a change of what is displayed
	///
	/// - Parameters:
	///   - range: the range of the text in the original string
	///   - delta: the change made
	func contentsEdited(range: NSRange, delta: Int) -> Bool {
		/// FIXME: implement
		// need to update the changed chunk if possible. If not, then reparse document
		return false
	}
	
	private func contextChanged() {
		contextDisposables.dispose()
		contentsDisposable?.dispose()
		contentsDisposable = nil
		// need to listen for currentDocument changes, then observe content changes of that document
		contextDisposables += context.signal.observeValues { [weak self] _ in
			guard let me = self, let context = me.context.value else { return }
			me.contextDisposables += context.parsedDocument.signal.observeValues { [weak self] _ in
				guard let me = self else { return }
				// document changed, re-observe contents
				me.documentChanged()
			}
			me.documentChanged()
		}
		documentChanged()
	}
	
	private func documentChanged() {
		contentsDisposable?.dispose()
		contentsDisposable = nil
		guard let context = editorContext else { return }
		contentsDisposable = context.parsedDocument.signal.observeValues { [weak self] _ in
			guard let me = self else { return }
			me.parseContent()
		}
	}
	
	private func parseContent() {
		guard let curDoc = context.value?.currentDocument.value,
			let newText = curDoc.currentContents
		else {
			outputView?.loadHTMLString("", baseURL: nil)
			return
		}
		let content = """
			document.getElementById('foobar').innerText = <b>blow me</b>;
		"""
		outputView?.evaluateJavaScript(content, completionHandler: nil)
		// TODO: send file directory as baseURL
		//outputView.loadHTMLString(newText, baseURL: nil)
	}
	
	private func escapeForJavascript(_ source: String) -> String {
		var string = source
		string = string.replacingOccurrences(of: "\\", with: "\\\\")
		string = string.replacingOccurrences(of: "\"", with: "\\\"")
		string = string.replacingOccurrences(of: "\'", with: "\\\'")
		string = string.replacingOccurrences(of: "\n", with: "\\n")
		string = string.replacingOccurrences(of: "\r", with: "\\r")
		// swift does not recognize this as a valid sequence needing escape
		// string = string.replacingOccurrences(of: "\f", with: "\\f")
		return string
	}
}
