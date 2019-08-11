//
//  LivePreviewController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/29/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import WebKit
import Rc2Common
import ClientCore
import SyntaxParsing
import ReactiveSwift
import Down
import MJLLogger

// code to extract a zip file with preview_support locally is commented out because of a bug where WKWebView tries to load with %20 in app support url, which fails

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

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController, WKUIDelegate, WKNavigationDelegate
{
	var contextualMenuDelegate: ContextualMenuDelegate?
	var sessionController: SessionController?
	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil) { didSet { contextChanged() }}
	private let contextDisposables = CompositeDisposable()
	private var contentsDisposable: Disposable?
	private var lineContiuationRegex: NSRegularExpression!
	private var openDoubleDollarRegex: NSRegularExpression!
	private var closeDoubleDollarRegex: NSRegularExpression!
	private var documentRoot: URL?
	private var initialDocumentLoaded = false
	private var needToLoadDocumentOnLoad = false
	private var resourcesExtracted = false
	private var readyForContent: Bool { return resourcesExtracted && needToLoadDocumentOnLoad }
	private var parseInProgress = false
	private var emptyNavigations: Set<WKNavigation> = []
	
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
		guard let regex = try? NSRegularExpression(pattern: "\\s+\\\\$", options: [.anchorsMatchLines]),
			let openRegex = try? NSRegularExpression(pattern: "^\\$\\$", options: []),
			let closeRegex = try? NSRegularExpression(pattern: "\\$\\$(\\s*)$", options: [])
			else { fatalError("regex failed to compile")}

		lineContiuationRegex = regex
		openDoubleDollarRegex = openRegex
		closeDoubleDollarRegex = closeRegex
		documentRoot = Bundle.main.url(forResource: "preview_support", withExtension: nil)
//		do {
//			documentRoot = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "preview_support")
//			documentRoot = URL(fileURLWithPath: documentRoot!.path.removingPercentEncoding!)
//			loadInitialPage()
//		} catch {
//			fatalError("failed to load live preview template file: \(error.localizedDescription)")
//		}
		ensureResourcesLoaded()
		outputView?.uiDelegate = self
		outputView?.navigationDelegate = self
	}
	
	/// called by the editor when the user has made an edit, resulting in a change of what is displayed
	///
	/// - Parameters:
	///   - range: the range of the text in the original string
	///   - delta: the change made
	func contentsEdited(range: NSRange, delta: Int) -> Bool {
		/// FIXME: implement
		// need to update the changed chunk if possible. If not, then reparse document
		parseContent()
		return true
	}
	
	private func loadInitialPage() {
		guard resourcesExtracted, needToLoadDocumentOnLoad,
			let headerUrl = Bundle.main.url(forResource: "customRmdHeader", withExtension: "html"),
			let footerUrl = Bundle.main.url(forResource: "customRmdFooter", withExtension: "html")
			else { return }
		do {
			let header = try String(contentsOf: headerUrl)
			let footer = try String(contentsOf: footerUrl)
			let nav = outputView?.loadHTMLString("\(header) \(footer)", baseURL: documentRoot)
			if let realNav = nav { emptyNavigations.insert(realNav) }
		} catch {
			fatalError("failed to load initial preview content: \(error)")
		}
	}

	/// called when the context property has been set
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
		if let context = context.value {
			contextDisposables += context.parsedDocument.signal.observeValues { [weak self] _ in
				guard let me = self else { return }
				// document changed, re-observe contents
				me.documentChanged()
			}
		}
		guard outputView != nil else {
			needToLoadDocumentOnLoad = true
			return
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
		parseContent()
	}
	
	/// parses the parsed document and loads it via javascript
	private func parseContent() {
		guard !parseInProgress else { return }
		guard let curDoc = context.value?.parsedDocument.value else {
			let curNav = outputView?.loadHTMLString("", baseURL: nil)
			if let realNave = curNav { emptyNavigations.insert(realNave)}
			return
		}
		parseInProgress = true
		defer { parseInProgress = false }
		var html = curDoc.frontMatter.value + "\n"
		let allChunks = curDoc.chunks
		for (chunkNumber, chunk) in allChunks.enumerated() {
			html += "<section index=\"\(chunkNumber)\">\n"
			html += htmlFor(chunk: chunk)
			html += "\n</section>\n"
		}
		html = escapeForJavascript(html)
		let command = "document.getElementsByTagName('body')[0].innerHTML = '\(html)'; MathJax.Hub.Queue([\"Typeset\",MathJax.Hub]);"
		outputView?.evaluateJavaScript(command, completionHandler: nil)
	}
	
	private func htmlFor(chunk: RmdChunk) -> String {
		switch chunk.chunkType {
		case .code:
			let code = htmlFor(code: chunk)
			return code
		case .docs:
			return htmlFor(markdownChunk: chunk)
		case .equation:
			return htmlForEquation(chunk: chunk)
		}
	}
	
	private func htmlFor(markdownChunk: RmdChunk) -> String {
		guard let chunk = markdownChunk as? TextChunk else { preconditionFailure("invalid chunk type") }
		let options: DownOptions = [.sourcePos, .unsafe]
		var adjustedText = chunk.rawText
		var inlineMap: [Int : String] = [:]
		var allChunks = chunk.inlineElements
		do {
			// store output strings for each chunk keyed on index
			for (inlineIdx, inlineChunk) in chunk.inlineElements.enumerated() {
				inlineMap[inlineIdx] = textFor(inlineChunk: inlineChunk, parent: chunk)
			}
			// replace those values with markers so they won't be converted to markdown
			for index in (0..<chunk.inlineElements.count).reversed() {
				guard let range = allChunks[index].chunkRange.toStringRange(adjustedText)
					else { preconditionFailure("failed to get range for chunk \(index)") }
				adjustedText = adjustedText.replacingCharacters(in: range, with: "🖍\(index)🖍")
			}
			// convert markdown to html
			adjustedText = try adjustedText.toHTML(options)
			// replace markers with inline text
			for  index in 0..<allChunks.count {
				adjustedText = adjustedText.replacingOccurrences(of: "🖍\(index)🖍", with: inlineMap[index]!)
			}
			return adjustedText
		} catch {
			Log.error("Failed to convert markdown to HTML: \(error)", .app)
		}
		return "<p>failed to parse markdown</p>\n"
	}
	
	private func textFor(inlineChunk: InlineChunk, parent: TextChunk) -> String {
		guard let inlineText = parent.contents.string.substring(from: inlineChunk.range)
			else { preconditionFailure("failed to get substring for inline chunk") }
		var icText = inlineText
		switch inlineChunk.chunkType {
		case .code:
			icText = inlineChunk.rawText
		case .equation:
			icText = "\\(\(inlineText)\\)"
		case .docs:
			preconditionFailure("inline chunk can't be markdown")
		}
		return icText
	}
	
	private func htmlFor(code: RmdChunk) -> String {
		return "<pre class=\"r\"><code>\(code.contents.string.addingUnicodeEntities)</code></pre>\n"
	}
	
	private func htmlForEquation(chunk: RmdChunk) -> String {
		var equationText = chunk.rawText
		equationText = lineContiuationRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "")
		equationText = openDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\[")
		equationText = closeDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\]")
		equationText = equationText.addingUnicodeEntities
		return "\n<p>\(equationText)</p>\n"

	}
	
	private func markdownFor(inlineEquation: InlineEquationChunk, parent: TextChunk) -> String {
		guard var code = parent.rawText.substring(from: inlineEquation.range) else {
			fatalError("invalid range for inline chunk")
		}
		code = code.replacingOccurrences(of: "^\\$", with: "\\(", options: .regularExpression)
		code = code.replacingOccurrences(of: "\\$$\\s", with: "\\) ", options: .regularExpression)
		return "<span class\"math inline\">\n\(code)</span>"
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
	
	private func ensureResourcesLoaded() {
		resourcesExtracted = true
		loadInitialPage()
//		guard let tarball = Bundle.main.url(forResource: "previewResources", withExtension: "tgz"), tarball.fileExists()
//			else { fatalError("failed to find previewResources in app bundle")
//		}
//
//		let tar = Process()
//		tar.currentDirectoryPath = documentRoot!.deletingLastPathComponent().path
//		tar.arguments = ["zxf", tarball.path]
//		tar.launchPath = "/usr/bin/tar"
//		tar.terminationHandler = { process in
//			guard process.terminationStatus == 0 else {
//				fatalError("help extraction failed: \(process.terminationReason.rawValue)")
//			}
//			DispatchQueue.main.async {
//				Log.info("preview resources loaded", .app)
//				self.resourcesExtracted = true
//				self.loadInitialPage()
//			}
//		}
//		tar.launch()
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		if emptyNavigations.contains(navigation) {
			emptyNavigations.remove(navigation)
			return
		}
		Log.info("did finish webView load")
		if needToLoadDocumentOnLoad {
			contextDisposables += context.value?.parsedDocument.signal.observeValues { [weak self] _ in
				guard let me = self else { return }
				// document changed, re-observe contents
				me.documentChanged()
			}
			needToLoadDocumentOnLoad = false
		}
//		if readyForContent {
			documentChanged()
//		}
	}
	
	func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void)
	{
		Log.info("An error from web view: \(message)", .app)
		completionHandler()
	}
}
