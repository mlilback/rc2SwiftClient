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
import Model
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

	/// to be called once by editor at load
	func setEditorContext(_ econtext: EditorContext?)
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler
{
	// required by OutputController, should use at some point
	weak var contextualMenuDelegate: ContextualMenuDelegate?

	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil)
	private var curDocDisposable: Disposable?
	private var didLoadView = false
	private var pageShellLoaded = false
	private let opQueue: OperationQueue = {
		let q = OperationQueue()
		q.maxConcurrentOperationCount = 1
		q.name = "preview display"
		q.qualityOfService = .userInitiated
		q.isSuspended = true
		return q
	}()

	internal var parserContext: ParserContext? { didSet {
		curDocDisposable?.dispose()
		if let pc = parserContext, let ppc = previousContext, ObjectIdentifier(pc) == ObjectIdentifier(ppc) {
			return
		}
		if lineContiuationRegex == nil {
			loadRegexes() // viewDidLoad might not have been called yet
		}
		curDocDisposable = parserContext?.parsedDocument.signal.observe(on: UIScheduler()).observeValues(documentChanged)
	} }
	private var previousContext: ParserContext?
	private var parsedDocument: RmdDocument? { return parserContext?.parsedDocument.value }
	private let mdownParser = MarkdownParser()
	private var previewData = [Int: PreviewIdCache]()
	private var currentPreview: PreviewIdCache?
	private var initialCodeLoaded = false
	private var previewRequestInProgress: Bool = false

	// regular expressions
	private var lineContiuationRegex: NSRegularExpression!
	private var openDoubleDollarRegex: NSRegularExpression!
	private var closeDoubleDollarRegex: NSRegularExpression!
	private let dataSourceRegex: NSRegularExpression = {
		let posPattern = #"""
		(?xi)data-sourcepos="(\d+):
		"""#
		// swiftlint:disable:next force_try
		return try! NSRegularExpression(pattern: posPattern, options: .caseInsensitive)
	}()

	/// true if packaged resources have been extracted into the app support folder
	private var resourcesExtracted = false
	/// stores navigation items that shouldn't have any effect
	private var emptyNavigations: Set<WKNavigation> = []

	private var documentRoot: URL?
	private var htmlRoot: URL?
	private var docHtmlLoaded = false

	@IBOutlet weak var outputView: WKWebView?
	private var webConfig: WKWebViewConfiguration?
	private var initNavigation: WKNavigation?

	// MARK: - standard overrides

	override func viewDidLoad() {
		super.viewDidLoad()
		loadRegexes()
		loadWebView()
		// for some reason the debugger show documentRoot as nil after this, even though po documentRoot?.absoluteString returns output
		documentRoot = Bundle.main.url(forResource: "FileTemplates", withExtension: nil)
		htmlRoot = Bundle.main.url(forResource: "preview_support", withExtension: nil)
		didLoadView = true
		docHtmlLoaded = false
		outputView?.uiDelegate = self
		outputView?.navigationDelegate = self
		// if have webview and wasn't loaded, suspend the queue
		ensureResourcesLoaded()
		context.signal.observeValues { (_) in
			print("got new context)")
		}
	}

	override func sessionChanged() {
		super.sessionChanged()
		loadPreviewIfNecessary()
	}

	// MARK: - notification handlers

	/// called by the editor when the user has made an edit, resulting in a change of what is displayed
	/// this likely means there are changes to consier reparsing
	///
	/// - Parameters:
	///   - range: the range of the text in the original string
	///   - delta: the change made
	func contentsEdited(contents: String, range: NSRange, delta: Int) -> Bool {

		// TODO: if change is to markdown or equation, we can manually update without saving and reparse.
		// never execute code chunks (happens on button click)
		// if paste with a chunk in it, we need to reparse. BUt we don't know that without a reparse.
		//
		
		// does nstext_ let un know when a paste or drag&drop happens vs typing.
		// if change was that, definately need to reparse
//		do {
//			try parser?.reparse()
//		} catch {
//			Log.warn("failed to parse rmd \(error)", .app)
//		}
//		colorizeHighlightAttributes()
		Log.info("contentsEdited called", .app)
//		updatePreview(updatedContents: contents)
		return true
	}

	/// called when the currentDocument of the EditorContext has changed
	private func documentChanged(newDocument: RmdDocument?) {
		guard didLoadView else { return } //don't parse if view not loaded
		if docHtmlLoaded || newDocument == parsedDocument  {
			Log.info("document changed with possible duplicate", .app)
		}
		guard let fileId = context.value?.currentDocument.value?.file.fileId else {
			// no file
			currentPreview = nil
			return
		}
		loadPreviewIfNecessary()
		if  var previewInfo = previewData[fileId]
		{
			// already have preview info
			previewInfo.codeHandler = PreviewCodeHandler(previewId: previewInfo.previewId)
			currentPreview = previewInfo
			previewInfo.codeHandler.clearCache()
		}
		refreshContent()
	}

	// MARK: - action handlers
	func executeChunk(number: Int) {

	}

	func executeChunkAndPrevious(number: Int) {
	}

	// MARK: - content presentation

	private func loadInitialPage() {
		guard !pageShellLoaded else { return }
		guard let headerUrl = Bundle.main.url(forResource: "customRmdHeader", withExtension: "html"),
			let footerUrl = Bundle.main.url(forResource: "customRmdFooter", withExtension: "html")
			else { fatalError("failed to find preview header/footer") }
		do {
			let headerContents = try String(contentsOf: headerUrl)
			let footerContents = try String(contentsOf: footerUrl)
			initNavigation = outputView?.loadHTMLString(headerContents + footerContents, baseURL: htmlRoot)
		} catch {
			fatalError("failed to load initial preview content: \(error)")
		}
	}

	/// parses the parsed document and loads it via javascript
	// swiftlint:disable:next cyclomatic_complexity
	private func updatePreview(updatedContents: String? = nil) {
		guard didLoadView else { return }

		// handle empty content
		guard let curDoc = parsedDocument, let curPreview = currentPreview else { return; }
		if docHtmlLoaded, updatedContents == nil, curDoc.attributedString.length > 0 { return }
		guard let contents = updatedContents ?? parserContext?.parsedDocument.value?.rawString
			else { Log.warn("current doc has no contents??"); return }
		guard curDoc.attributedString.string != updatedContents else { return }
		// update the parsed document, update the webview
		// swiftlint:disable:next force_try
		var changedChunkIndexes = try! RmdDocument.update(document: curDoc, with: contents) ?? []
		// TODO: cacheCode needs to be async
		// add to changedChunkIndexes any chunks that need to udpated because of changes to R code
		if changedChunkIndexes.count > 0 {
			curPreview.codeHandler.cacheCode(changedChunks: &changedChunkIndexes, in: curDoc)
		} else {
			curPreview.codeHandler.cacheAllCode(in: curDoc)
		}
		// handle changes
		if changedChunkIndexes.count > 0 {
			Log.info("udpating just chunks \(changedChunkIndexes)")
			for chunkNumber in changedChunkIndexes {
				let chunk = curDoc.chunks[chunkNumber]

				var html = htmlFor(chunk: chunk, index: chunkNumber) // don't want the wrapping section ala htmlWrapper()
				if chunk.chunkType != .equation {
					html = escapeForJavascript(html)
				}

				var command = "$(\"section[index='\(chunkNumber)']\").html('\(html)');"
				if chunk.chunkType == .equation {
					command += "MathJax.typeset()"
				}
				runJavascript(command) { (_, err) in
					guard err == nil else {
						Log.warn("javascript failed", .app)
						return
					}
					Log.info("javascript worked")
				}
			}
			runJavascript("updateSectionToolbars()")
		} else { // no changes, so just refresh everything
			refreshContent()
		}
	}

	func refreshContent() {
		guard let curDoc = parsedDocument, currentPreview != nil else {
			load(html: "")
			return
		}
		if !(currentPreview?.codeHandler.contentCached ?? false) {
			currentPreview?.codeHandler.cacheAllCode(in: curDoc)
		}
		var html =  ""
		for (chunkNumber, chunk) in curDoc.chunks.enumerated() {
			let chtml = htmlWrapper(chunk: chunk, chunkNumber: chunkNumber)
			html += chtml
		}
		docHtmlLoaded = true
		load(html: html)
		runJavascript("updateSectionToolbars(); MathJax.typeset()") { (_, error) in
			guard error != nil else { return }
			let msg = error.debugDescription
			Log.info("got error refreshing content: \(msg)")
		}
	}

	private func htmlWrapper(chunk: RmdDocumentChunk, chunkNumber: Int) -> String {
		var html = ""
		let descriptor = chunk.isInline ? "inline" : "section"

		html += "<\(descriptor) index=\"\(chunkNumber)\" type=\"\(chunk.chunkType)\">\n"
		if !chunk.isInline {
			html += "<sectionToolbar index=\"\(chunkNumber)\" type=\"\(chunk.chunkType)\"></sectionToolbar>\n"
			html += "<sectionContent index=\"\(chunkNumber)\">\n"
		}
		html += htmlFor(chunk: chunk, index: chunkNumber)
		if !chunk.isInline {
			html += "\n</sectionContent>\n"
		}
		html += "\n</\(descriptor)>\n"
		return html
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
		guard let rHandler = currentPreview?.codeHandler else {
			Log.warn("asked to generate R code w/o context")
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
		// FIXME: need to use fifo queue for all loads and javacripts. run immediately if queue empty, otherwise next item run when didFinish called
//		opQueue.addOperation {
//			let nav = self.outputView?.loadHTMLString(html, baseURL: self.htmlRoot)
//			if let realNav = nav { self.emptyNavigations.insert(realNav) }
//		}
		opQueue.addOperation { [weak self] in
			guard let me = self else { return }
			let sema = DispatchSemaphore(value: 1)
			let encoded = html.data(using: .utf8)!.base64EncodedString()
			let realString = "updateBody(" + "'" + encoded + "')"
			DispatchQueue.main.async {
				me.outputView?.evaluateJavaScript(realString) { (_, _) in
					sema.signal()
				}
				sema.wait()
			}
		}
	}

	private func runJavascript(_ script: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
		opQueue.addOperation { [weak self] in
			guard let me = self else { return }
			let sema = DispatchSemaphore(value: 1)
			let encoded = script.data(using: .utf8)!.base64EncodedString()
			let realString = "executeScript(" + "'" + encoded + "')"
			DispatchQueue.main.async {
				me.outputView?.evaluateJavaScript(realString) { (val, err) in
					completionHandler?(val, err)
					sema.signal()
				}
				sema.wait()
			}
		}
	}

	// MARK: - Preview
	
	@discardableResult
	private func loadPreviewIfNecessary() -> Bool {
		guard !initialCodeLoaded, let fileId = context.value?.currentDocument.value?.file.fileId else { return false }
		// TODO: update this to use appStatus
		guard !initialCodeLoaded else { return true }
		initialCodeLoaded = true
		requestPreviewId(fileId: fileId).startWithResult { [weak self] (result) in
			guard let me = self else { Log.error("previewId received without self", .app); return }
			switch result {
			case .failure(let error):
				Log.error("failed to get previewId: \(error)", .app)
			case .success(let value):
				me.requestUpdate(previewId: value, chunkId: -1, includePrevious: true).startWithCompleted {
					Log.info("got initial code update")
					me.initialCodeLoaded = false
					me.refreshContent()
				}
			}
		}
		return true
	}
	
	private func requestPreviewId(fileId: Int) -> SignalProducer<Int, Rc2Error> {
		let handler = SignalProducer<Int, Rc2Error> { observer, _ in
				self.session.requestPreviewId(fileId: fileId).startWithResult { [weak self] (result) in
				guard let me = self else {
					let err = Rc2Error(type: .network, nested: AppError(.selfInvalid), severity: .error, explanation: "failed to update preview")
					observer.send(error: err)
					return
				}
				switch result {
				case .success(let previewId):
					Log.info("got previewId \(previewId)")
					let codeHandler = PreviewCodeHandler(previewId: previewId)
					let cacheEntry = PreviewIdCache(previewId: previewId, fileId: fileId, codeHandler: codeHandler)
					me.previewData[previewId] = cacheEntry
					me.currentPreview = cacheEntry
					observer.send(value: previewId)
					observer.sendCompleted()
					DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
						self?.refreshContent()
					}
				case .failure(let err):
					Log.warn("requestPreviewId got error \(err)")
					observer.send(error: err)
				}
			}
		}
		return handler
	}

	private func requestUpdate(previewId: Int, chunkId: Int, includePrevious: Bool = false) -> SignalProducer<Void, Rc2Error> {
		guard var preview = previewData[previewId] else {
			let rerr = Rc2Error(type: .application, nested: PrecviewError.failedToUpdate, severity: .warning)
			Log.info("Failed to find preview \(previewId)", .app)
			return SignalProducer<Void, Rc2Error>(error: rerr)
		}
		let handler = SignalProducer<Void, Rc2Error> { [weak self] observer, _ in
			guard let me = self else { return }
			preview.updateObserver = observer
			// chunkIds will include previous
			let producer = me.session.updatePreviewChunks(previewId: previewId, chunkId: chunkId, includePrevious: includePrevious, updateId: "preview \(previewId)")
			producer.startWithCompleted {
				preview.updateObserver = nil
			}
			
		}
		return handler
	}
	
	// MARK: - utility
	
	func setEditorContext(_ econtext: EditorContext?) {
		precondition(context.value == nil)
		context.value = econtext
	}
	
	private func loadWebView() {
		let prefs = WKPreferences()
		prefs.minimumFontSize = 9.0
		prefs.javaEnabled = false
		prefs.javaScriptCanOpenWindowsAutomatically = false
		let config = WKWebViewConfiguration()
		config.preferences = prefs
		config.applicationNameForUserAgent = "Rc2"
		config.allowsAirPlayForMediaPlayback = true
		webConfig = config
		webConfig?.userContentController.add(self, name: "previewHandler")
		let newwk = WKWebView(frame: outputView!.frame, configuration: config)
		newwk.translatesAutoresizingMaskIntoConstraints = false
		outputView?.superview?.addSubview(newwk)
		outputView?.removeFromSuperview()
		outputView = newwk
		outputView?.uiDelegate = self
		outputView?.navigationDelegate = self
		outputView?.widthAnchor.constraint(equalTo: newwk.superview!.widthAnchor).isActive = true
		outputView?.heightAnchor.constraint(equalTo: newwk.superview!.heightAnchor).isActive = true
		outputView?.centerYAnchor.constraint(equalTo: newwk.superview!.centerYAnchor).isActive = true
		outputView?.centerXAnchor.constraint(equalTo: newwk.superview!.centerXAnchor).isActive = true

	}

	private func loadRegexes() {
		guard lineContiuationRegex == nil else { return }
		guard let regex = try? NSRegularExpression(pattern: "\\s+\\\\$", options: [.anchorsMatchLines]),
			let openRegex = try? NSRegularExpression(pattern: "^\\$\\$", options: []),
			let closeRegex = try? NSRegularExpression(pattern: "\\$\\$(\\s*)$", options: [])
			else { fatalError("regex failed to compile") }
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
		if navigation == initNavigation {
			pageShellLoaded = true
//			runJavascript("updateSectionToolbars(); MathJax.typeset()")
			opQueue.isSuspended = false
		}
		if emptyNavigations.contains(navigation) {
			emptyNavigations.remove(navigation)
			return
		}
		guard let _ = parsedDocument else { return }
		updatePreview()
	}

	func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void)
	{
		Log.info("An error from web view: \(message)", .app)
		completionHandler()
	}

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if let dict = message.body as? [String: Any], let name = dict["name"] as? String {
			if name == "toolClicked" {
				guard let str = dict["chunkNumber"] as? String,
					let chunkNum = Int(str),
					let actionName = dict["action"] as? String
					else { return }
				switch actionName {
				case "execute":
					executeChunk(number: chunkNum)
				case "executePrevious":
						executeChunkAndPrevious(number: chunkNum)
				default:
						Log.info("invalid action from preview: \(actionName)")
				}
			}

			return
		}
		if message.name == "pageLoaded" {
			Log.info("page loaded")
		} else if message.name == "previewHandler" {
			//ignore
		} else {
			Log.info("unknown message posted from preview")
		}
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

/// used to cache previews so old ones can be removed to free memory pressure
private struct PreviewIdCache: Equatable {
	init(previewId: Int, fileId: Int, codeHandler: PreviewCodeHandler) {
		self.previewId = previewId
		self.fileId = fileId
		self.codeHandler = codeHandler
		self.updateObserver = nil
	}

	static func == (lhs: PreviewIdCache, rhs: PreviewIdCache) -> Bool {
		return lhs.fileId == rhs.fileId && lhs.previewId == rhs.previewId
	}

	let previewId: Int
	let fileId: Int
	var codeHandler: PreviewCodeHandler
	var lastAccess: TimeInterval = Date.timeIntervalSinceReferenceDate
	var updateObserver: Signal<Void, Rc2Error>.Observer?
}

// MARK: - SessionPreviewDelegate
extension LivePreviewDisplayController: SessionPreviewDelegate {
	func previewIdReceived(response: SessionResponse.PreviewInitedData) {
		// do nothing because signal value triggers setting it
		Log.info("got preview Id \(response.previewId)")
	}

	func previewUpdateReceived(response: SessionResponse.PreviewUpdateData) {
		guard let doc = parsedDocument else {
			Log.warn("preview update witout a document", .app)
			return
		}
		guard var preview = previewData[response.previewId] else { return }
		var toCache = [response.chunkId]
		preview.codeHandler.cacheCode(changedChunks: &toCache, in: doc)
		let html = preview.codeHandler.htmlForChunk(document: doc, number: response.chunkId)
		preview.lastAccess = Date.timeIntervalSinceReferenceDate
		let script = """
		$("sectionContent[index=\(response.chunkId)]").innerHtml = \(html)")
		"""
		runJavascript(script)
	}
}
