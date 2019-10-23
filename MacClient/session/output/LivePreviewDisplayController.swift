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
	///   - contents: the propsed updated contents
	///   - range: the range of the text in the original string
	///   - delta: the change made
	/// - Returns: true if the changes should be saved to the current document's editedContents causing a reparse
	func contentsEdited(contents: String, range: NSRange, delta: Int) -> Bool
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController, WKUIDelegate, WKNavigationDelegate
{
	// required by OutputController, should use at some point
	var contextualMenuDelegate: ContextualMenuDelegate?
	var sessionController: SessionController? { didSet {
		guard let session = sessionController else { codeHandler = nil; return }
		codeHandler = PreviewCodeHandler(sessionController: session)
	}}
	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil)
	private var curDocDisposable: Disposable?
	private var didLoadView = false

	private var parsedDocument: RmdDocument? = nil
	private let mdownParser = MarkdownParser()
	private var parseInProgress = false
	private var codeHandler: PreviewCodeHandler?

	// regular expressions
	private var lineContiuationRegex: NSRegularExpression!
	private var openDoubleDollarRegex: NSRegularExpression!
	private var closeDoubleDollarRegex: NSRegularExpression!
	private let dataSourceRegex: NSRegularExpression = {
		let posPattern = #"""
		(?xi)data-sourcepos="(\d+):
		"""#
		return try! NSRegularExpression(pattern: posPattern, options: .caseInsensitive)
	}()

	/// true if packaged resources have been extracted into the app support folder
	private var resourcesExtracted = false
	/// stores navigation items that shouldn't have any effect
	private var emptyNavigations: Set<WKNavigation> = []
	
	private var documentRoot: URL?
	private var headerContents = ""
	private var footerContents = ""
	private var lastContents: String?


	var emptyContents: String { "\(headerContents) \(footerContents)" }
	
	var editorContext: EditorContext? {
		get { return context.value }
		set {
			// do nothing if same as existing context
			if let c1 = context.value, let c2 = newValue, c1.id == c2.id { return }
			context.value = newValue
			contextChanged()
		}
	}
	
	@IBOutlet weak var outputView: WKWebView?
	
	// MARK: - standard overrides
	
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
		didLoadView = true
		ensureResourcesLoaded()
		outputView?.uiDelegate = self
		outputView?.navigationDelegate = self
	}
	
	// MARK: - notification handlers
	
	/// called by the editor when the user has made an edit, resulting in a change of what is displayed
	///
	/// - Parameters:
	///   - range: the range of the text in the original string
	///   - delta: the change made
	func contentsEdited(contents: String, range: NSRange, delta: Int) -> Bool {
		updatePreview(updatedContents: contents)
		return true
	}
	
	/// called when the currentDocument of the EditorContext has changed
	private func documentChanged() {
		parsedDocument = nil
		lastContents = nil
		updatePreview()
	}
		
	/// called when the context property has been set
	private func contextChanged() {
		lastContents = nil
		parsedDocument = nil
		curDocDisposable?.dispose()
		curDocDisposable = editorContext?.currentDocument.signal.observeValues({ [weak self] newDoc in
			self?.documentChanged()
		})
		if !resourcesExtracted {
			ensureResourcesLoaded()
		}
		documentChanged()
	}
	
	// MARK: - content presentation
	
	private func loadInitialPage() {
		guard headerContents.count == 0 else { return }
		guard let headerUrl = Bundle.main.url(forResource: "customRmdHeader", withExtension: "html"),
			let footerUrl = Bundle.main.url(forResource: "customRmdFooter", withExtension: "html")
			else { fatalError("failed to find preview header/footer") }
		do {
			headerContents = try String(contentsOf: headerUrl)
			footerContents = try String(contentsOf: footerUrl)
			updatePreview()
		} catch {
			fatalError("failed to load initial preview content: \(error)")
		}
	}
	
	/// parses the parsed document and loads it via javascript
	private func updatePreview(updatedContents: String? = nil) {
		guard !parseInProgress else { return }
		guard didLoadView else { return }
		var updateParse = true
		
		// if a new document was generated, need to clear old contents after webview is updated
		var clearLastContents = false
		defer { if clearLastContents { self.lastContents = nil} }
		
		// handle initial parsing
		if parsedDocument == nil {
			// need to do initial load. might be no contents if called before document loaded
			guard let contents = context.value?.currentDocument.value?.currentContents
				else { return }
			do {
				parsedDocument = try RmdDocument(contents: contents)
				updateParse = false
				clearLastContents = true
			} catch {
				Log.warn("error during initial parse: \(error)")
				return
			}
		}
		
		// handle empty content
		guard let curDoc = parsedDocument else {
			load(html: emptyContents)
			return
		}
		guard let contents = updatedContents ?? context.value?.currentDocument.value?.currentContents
			else { Log.warn("current doc has no contents??"); return }
		if contents == lastContents { return }
		
		// update the parsed document, update the webview
		parseInProgress = true
		defer { parseInProgress = false }
		var changedChunkIndexes = try! RmdDocument.update(document: curDoc, with: contents) ?? []
		// TODO: cacheCode needs to be async
		// add to changedChunkIndexes any chunks that need to udpated because of changes to R code
		codeHandler?.cacheCode(changedChunks: &changedChunkIndexes, in: curDoc)
		// handle changes
		if changedChunkIndexes.count > 0 {
			Log.info("udpating just chunks \(changedChunkIndexes)")
			for chunkNumber in changedChunkIndexes {
				let chunk = curDoc.chunks[chunkNumber]
				let html = escapeForJavascript(htmlFor(chunk: chunk, index: chunkNumber))
				let command = "$(\"section[index='\(chunkNumber)']\").html('\(html)'); MathJax.typeset()"
				outputView?.evaluateJavaScript(command, completionHandler: nil)
			}
		} else { // no changes, so just refresh everything
			var html =  ""
			for (chunkNumber, chunk) in curDoc.chunks.enumerated() {
				html += "<section index=\"\(chunkNumber)\">\n"
				html += htmlFor(chunk: chunk, index: chunkNumber)
				html += "\n</section>\n"
			}
			load(html: "\(headerContents)\n\(html)\n\(footerContents)")
		}
	}
	
	private func htmlFor(chunk: RmdChunk, index: Int) -> String {
		switch chunk.chunkType {
		case .code:
			let code = rHtmlFor(code: chunk, index: index)
			return code
		case .docs:
			return htmlFor(markdownChunk: chunk, index: index)
		case .equation:
			return htmlForEquation(chunk: chunk)
		}
	}
	
	private func htmlFor(markdownChunk: RmdChunk, index: Int) -> String {
		guard let chunk = markdownChunk as? TextChunk else { preconditionFailure("invalid chunk type") }
		let html = mdownParser.htmlFor(markdown: chunk.rawText)
		// modify source position to include chunk number
		_ = dataSourceRegex.replaceMatches(in: html, range: NSRange(location: 0, length: html.length), withTemplate: "data-sourcepos=\"\(index).$2")
		return html as String
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
	
	private func rHtmlFor(code chunk: RmdChunk, index: Int) -> String {
		guard let rHandler = codeHandler else {
			Log.warn("asked to generate R code w/o context");
			return "<pre class=\"r\"><code>\(chunk.contents.string.addingUnicodeEntities)</code></pre>\n"
		}
		let html = rHandler.htmlForChunk(number: index)
		return html
	}
	
	private func htmlForEquation(chunk: RmdChunk) -> String {
		var equationText = chunk.rawText
		equationText = lineContiuationRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "")
		equationText = openDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\[")
		equationText = closeDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\]")
		equationText = equationText.addingUnicodeEntities
		return "\n<div class=\"equation\">\(equationText)</div>\n"

	}
	
	private func markdownFor(inlineEquation: InlineEquationChunk, parent: TextChunk) -> String {
		guard var code = parent.rawText.substring(from: inlineEquation.range) else {
			fatalError("invalid range for inline chunk")
		}
		code = code.replacingOccurrences(of: "^\\$", with: "\\(", options: .regularExpression)
		code = code.replacingOccurrences(of: "\\$$\\s", with: "\\) ", options: .regularExpression)
		return "<span class\"math inline\">\n\(code)</span>"
	}
	
	/// replaces the visible html document
	/// - Parameter html: the new html to display
	private func load(html: String)  {
		let nav = outputView?.loadHTMLString(html, baseURL: documentRoot)
		if let realNav = nav { emptyNavigations.insert(realNav) }
	}
	
	// MARK: - utility
	
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
	
	/// verifies that all necessary steps have been taken before loading the initial page. Also extracts compressed resources into application support
	private func ensureResourcesLoaded() {
		guard didLoadView else { return }
		resourcesExtracted = true
		loadInitialPage()
		// were having problems with old zip method. Need to decide if need to expand.
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

	// MARK: - WebKit Delegate(s) methods
	
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		if emptyNavigations.contains(navigation) {
			emptyNavigations.remove(navigation)
			return
		}
		Log.info("did finish webView load")
		guard let _ = parsedDocument else { return }
		updatePreview()
	}
	
	func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void)
	{
		Log.info("An error from web view: \(message)", .app)
		completionHandler()
	}

	// MARK: - embedded types
	
	private class MarkdownParser {
		let allocator: UnsafeMutablePointer<cmark_mem>
		let cmarkOptions = CMARK_OPT_SOURCEPOS | CMARK_OPT_FOOTNOTES
		let parser: UnsafeMutablePointer<cmark_parser>?
		let extensions: UnsafeMutablePointer<cmark_llist>? = nil

		init() {
			allocator = cmark_get_default_mem_allocator()
			parser = cmark_parser_new(cmarkOptions)
			let tableExtension = cmark_find_syntax_extension("table")
			let strikeExtension = cmark_find_syntax_extension("strikethrough")
			cmark_llist_append(allocator, extensions, tableExtension)
			cmark_llist_append(allocator, extensions, strikeExtension)
		}
		
		func htmlFor(markdown: String) -> NSMutableString {
			markdown.withCString( { chars in
				cmark_parser_feed(parser, chars, strlen(chars))
			})
			let htmlDoc = cmark_parser_finish(parser)
			let html = NSMutableString(cString: cmark_render_html_with_mem(htmlDoc, cmarkOptions, extensions, allocator), encoding: String.Encoding.utf8.rawValue)!
			return html
		}
		
		deinit {
			cmark_llist_free(allocator, extensions)
			cmark_parser_free(parser)
		}
	}
}


