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
import Networking
import ReactiveSwift
import MJLLogger

// code to extract a zip file with preview_support locally is commented out because of a bug where WKWebView tries to load with %20 in app support url, which fails

protocol LivePreviewOutputController {
	/// allows preview editor to tell display controller what the current context is so it can monitor the current document
//	var editorContext: EditorContext? { get set }
	
	var parserContext: ParserContext? { get set }
	
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

	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil)
	private var curDocDisposable: Disposable?
	private var didLoadView = false

	internal var parserContext: ParserContext? { didSet {
		curDocDisposable?.dispose()
		loadRegexes() // viewDidLoad might not have been called yet
		curDocDisposable = parserContext?.parsedDocument.signal.observeValues(documentChanged)
	} }
	private var parsedDocument: RmdDocument? { return parserContext?.parsedDocument.value }
	private let mdownParser = MarkdownParser()
//	private var parseInProgress = false
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
	private var htmlRoot: URL?
	private var headerContents = ""
	private var footerContents = ""
	private var docHtmlLoaded = false

	var emptyContents: String { "\(headerContents) \(footerContents)" }
	
	@IBOutlet weak var outputView: WKWebView?
	
	// MARK: - standard overrides
	
	override func viewDidLoad() {
		super.viewDidLoad()
		loadRegexes()
		// for some reason the debugger show documentRoot as nil after this, even though po documentRoot?.absoluteString returns output
		documentRoot = Bundle.main.url(forResource: "FileTemplates", withExtension: nil)
		htmlRoot = Bundle.main.url(forResource: "preview_support", withExtension: nil)
		didLoadView = true
		docHtmlLoaded = false
		outputView?.uiDelegate = self
		outputView?.navigationDelegate = self
		ensureResourcesLoaded()
	}
	
	override func sessionChanged() {
		super.sessionChanged()
		guard sessionOptional != nil, let pcontext = parserContext else { codeHandler = nil; return }
		// chicken/egg problem with parserContext didSet. this is conditionally done in both
		codeHandler = PreviewCodeHandler(session: session, docSignal: pcontext.parsedDocument.signal)

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
	private func documentChanged(newDocument: RmdDocument?) {
		guard didLoadView else { return } //don't parse if view not loaded
		if docHtmlLoaded || newDocument == parsedDocument  {
			Log.info("document changed with possiblel duplicate", .app)
		}
		if  nil == codeHandler, let pcontext = parserContext {
			codeHandler = PreviewCodeHandler(session: session, docSignal: pcontext.parsedDocument.signal)
		}
		codeHandler?.clearCache()
		refreshContent()
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
//		guard !parseInProgress else { return }
		guard didLoadView else { return }

		// handle empty content
		guard let curDoc = parsedDocument else {
			load(html: emptyContents)
			return
		}
		if docHtmlLoaded, updatedContents == nil, curDoc.attributedString.length > 0 { return }
		guard let contents = updatedContents ?? parserContext?.parsedDocument.value?.rawString
			else { Log.warn("current doc has no contents??"); return }
		guard curDoc.attributedString.string != updatedContents else { return }
		// update the parsed document, update the webview
//		parseInProgress = true
//		defer { parseInProgress = false }
		var changedChunkIndexes = try! RmdDocument.update(document: curDoc, with: contents) ?? []
		// TODO: cacheCode needs to be async
		// add to changedChunkIndexes any chunks that need to udpated because of changes to R code
		if changedChunkIndexes.count > 0 {
			codeHandler?.cacheCode(changedChunks: &changedChunkIndexes, in: curDoc)
		} else {
			codeHandler?.cacheAllCode(in: curDoc)
		}
		// handle changes
		if changedChunkIndexes.count > 0 {
			Log.info("udpating just chunks \(changedChunkIndexes)")
			for chunkNumber in changedChunkIndexes {
				let chunk = curDoc.chunks[chunkNumber]
				var html = htmlFor(chunk: chunk, index: chunkNumber)
				html = escapeForJavascript(html)
				
				let command = "$(\"section[index='\(chunkNumber)']\").html('\(html)'); MathJax.typeset()"
//				let command = "document.querySelector('section[index=\(chunkNumber)]').html('\(html)'); MathJax.typeset(); debugger;"
				outputView?.evaluateJavaScript(command, completionHandler: nil)
			}
		} else { // no changes, so just refresh everything
			refreshContent()
		}
	}
	
	func refreshContent() {
		guard let curDoc = parsedDocument else {
			load(html: emptyContents)
			return
		}
		if !codeHandler!.contentCached {
			codeHandler!.cacheAllCode(in: curDoc)
		}
		var html =  ""
		for (chunkNumber, chunk) in curDoc.chunks.enumerated() {
			let descriptor = chunk.isInline ? "inline" : "section"
			html += "<\(descriptor) index=\"\(chunkNumber)\">\n"
			html += htmlFor(chunk: chunk, index: chunkNumber)
			html += "\n</\(descriptor)>\n"
		}
		docHtmlLoaded = true
		load(html: "\(headerContents)\n\(html)\n\(footerContents)")
		outputView?.evaluateJavaScript("MathJax.typeset()", completionHandler: nil)
	}
	
	private func htmlFor(chunk: RmdDocumentChunk, index: Int) -> String {
		switch RootChunkType(chunk.chunkType) {
		case .code:
			let code = rHtmlFor(code: chunk, index: index)
			return code
		case .markdown:
			return htmlFor(markdownChunk: chunk, index: index)
		case .equation:
			return htmlForEquation(chunk: chunk)
		}
	}
	
	private func htmlFor(markdownChunk: RmdDocumentChunk, index: Int) -> String {
		var chunkString = parsedDocument!.string(for: markdownChunk)
		// replace all inline chunks with a placeholder
		for (idx, ichunk) in markdownChunk.children.reversed().enumerated() {
			guard let range = Range<String.Index>(ichunk.chunkRange, in: chunkString) else { fatalError("invalid range") }
			chunkString = chunkString.replacingCharacters(in: range, with: "!IC-\(idx)!")
		}
		// convert markdown to html
		let html = mdownParser.htmlFor(markdown: chunkString)
		// restore inline chunks. reverse so don't invalidate later ranges
		for idx in (0..<markdownChunk.children.count).reversed() {
			let replacement = textFor(inlineChunk: markdownChunk.children[idx], parent: markdownChunk)
			html.replaceOccurrences(of: "!IC-\(idx)!", with: replacement, options: [], range: NSRange(location: 0, length: html.length))
		}
		// modify source position to include chunk number
		_ = dataSourceRegex.replaceMatches(in: html, range: NSRange(location: 0, length: html.length), withTemplate: "data-sourcepos=\"\(index).$2")
		return html as String
	}
	
	private func textFor(inlineChunk: RmdDocumentChunk, parent: RmdDocumentChunk) -> String {
		guard let doc = parsedDocument else { fatalError("textFor called w/o a document") }
		let inlineText = doc.string(for: inlineChunk, type: .inner)
		var icText = inlineText
		switch inlineChunk.chunkType {
		case .inlineCode:
			icText = doc.string(for: inlineChunk, type: .outer)
		case .inlineEquation:
			icText = "\\(\(inlineText)\\)"
		default:
			preconditionFailure("chunk isn't inline")
		}
		return icText
	}
	
	private func rHtmlFor(code chunk: RmdDocumentChunk, index: Int) -> String {
		guard let doc = parsedDocument else { fatalError("htmlFor called w/o a document") }
		guard let rHandler = codeHandler else {
			Log.warn("asked to generate R code w/o context");
			return "<pre class=\"r\"><code>\(doc.string(for: chunk, type: .inner).addingUnicodeEntities)</code></pre>\n"
		}
		let html = rHandler.htmlForChunk(document: doc, number: index)
		return html
	}
	
	private func htmlForEquation(chunk: RmdDocumentChunk) -> String {
		guard let doc = parsedDocument else { fatalError("htmlForEquationi called w/o a document") }
		var equationText = doc.string(for: chunk)
		equationText = lineContiuationRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "")
		equationText = openDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\[")
		equationText = closeDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\]")
		equationText = equationText.addingUnicodeEntities
		return "\n<div class=\"equation\">\(equationText)</div>\n"

	}
	
	private func markdownFor(inlineEquation: RmdDocumentChunk) -> String {
		guard let doc = parsedDocument else { fatalError("textFor called w/o a document") }
		var code = doc.string(for: inlineEquation, type: .inner)
		code = code.replacingOccurrences(of: "^\\$", with: "\\(", options: .regularExpression)
		code = code.replacingOccurrences(of: "\\$$\\s", with: "\\) ", options: .regularExpression)
		return "<span class\"math inline\">\n\(code)</span>"
	}
	
	/// replaces the visible html document
	/// - Parameter html: the new html to display
	private func load(html: String)  {
		let nav = outputView?.loadHTMLString(html, baseURL: htmlRoot)
		if let realNav = nav { emptyNavigations.insert(realNav) }
	}
	
	// MARK: - utility
	
	private func loadRegexes() {
		guard lineContiuationRegex == nil else { return }
		guard let regex = try? NSRegularExpression(pattern: "\\s+\\\\$", options: [.anchorsMatchLines]),
			let openRegex = try? NSRegularExpression(pattern: "^\\$\\$", options: []),
			let closeRegex = try? NSRegularExpression(pattern: "\\$\\$(\\s*)$", options: [])
			else { fatalError("regex failed to compile")}
		lineContiuationRegex = regex
		openDoubleDollarRegex = openRegex
		closeDoubleDollarRegex = closeRegex
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


