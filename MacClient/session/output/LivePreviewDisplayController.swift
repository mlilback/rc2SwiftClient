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

// TODO: migrate all code about generate html of any kind to PreviewCodeCache
// needs to tell cache to update code chunks when user has asked

// code to extract a zip file with preview_support locally is commented out because of a bug where WKWebView tries to load with %20 in app support url, which fails

extension NSNotification.Name {
	/// Sent when a preview update has started and the editor should be disabled. The object is the session.
	/// The userInfo dictilonary contains the `fileId` as an Int.
	static let previewUpdateStarted = NSNotification.Name("previewUpdateStarted")
	/// sent when a preview update has finished and the editor can be enabled
	static let previewUpdateEnded = NSNotification.Name("previewUpdateEnded")
}

protocol LivePreviewOutputController {
	typealias SaveFactory = () -> SignalProducer<(), Rc2Error>
	var parserContext: ParserContext? { get set }
	
	var saveProducer: SaveFactory? { get set }
 
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
	
	/// Updates the entire preview with the contents of the editor
	func updatePreview()
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler
{
	// required by OutputController, should use at some point
	weak var contextualMenuDelegate: ContextualMenuDelegate?

	private var editorContext: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil)
	private var curParsedDocDisposable: Disposable?
	private var curEditorDocDisposable: Disposable?
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

	internal var saveProducer: SaveFactory?
	internal var parserContext: ParserContext? { didSet {
		curParsedDocDisposable?.dispose()
		if let pc = parserContext, let ppc = previousContext, ObjectIdentifier(pc) == ObjectIdentifier(ppc) {
			return
		}
		curParsedDocDisposable = parserContext?.parsedDocument.signal.observe(on: UIScheduler()).observeValues(documentChanged)
	} }
	private var previousContext: ParserContext?
	private var parsedDocument: RmdDocument? { return parserContext?.parsedDocument.value }
	private var previewData = [Int: PreviewIdCache]()
	private var currentPreview: PreviewIdCache?
	private var initialCodeLoaded = false
	private var previewRequestInProgress: Bool = false

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
		editorContext.signal.observeValues { (_) in
			print("got new context)")
		}
	}

	override func sessionChanged() {
		super.sessionChanged()
		session.previewDelegate = self
		loadPreviewIfNecessary()
	}

	// MARK: - notification handlers

	/// called by the editor when the user has made an edit, resulting in a change of what is displayed
	/// this likely means there are changes to consider reparsing
	///
	/// - Parameters:
	///   - range: the range of the text in the original string
	///   - delta: the change made
	func contentsEdited(contents: String, range: NSRange, delta: Int) -> Bool {

		// TODO: if change is to markdown or equation, we can manually update without saving and reparse.
		// never execute code chunks (happens on button click)
		// if paste with a chunk in it, we need to reparse. BUt we don't know that without a reparse.
		//

		// we need to know when contents edited was called because of a paste so we can not require a reparse if only a single markdown chunk was affected. Is the knowledeable without the new delegate method added to sessioneditordelegate (which the editor conforms to). What happens on delete? maybe for now always reparts on anything bigger than a few words? Or any paste with $$ or ``` ?
		
		// does nstext_ let un know when a paste or drag&drop happens vs typing.
		// if change was that, definately need to reparse
//		do {
//			try parser?.reparse()
//		} catch {
//			Log.warn("failed to parse rmd \(error)", .app)
//		}
//		colorizeHighlightAttributes()
		Log.info("contentsEdited called", .app)
		
		// TODO: first try always reparsing. then skip reparse if no ` or $
		updatePreview(updatedContents: contents)
		return true
	}

	/// called when the currentDocument of the EditorContext has changed
	private func documentChanged(newDocument: RmdDocument?) {
		guard didLoadView else { return } //don't parse if view not loaded
		if docHtmlLoaded || newDocument == parsedDocument  {
			Log.info("document changed with possible duplicate", .app)
		}
		guard let fileId = editorContext.value?.currentDocument.value?.file.fileId else {
			// no file
			currentPreview = nil
			return
		}
		// FIXME: following will not load the new editorDocument because initialCodeLoaded is true if this is not the first document.
		loadPreviewIfNecessary()
		// if there isn't previewData created by the above call, it is being created in the background. refreshContent() will be called when completed
		guard var previewInfo = previewData[fileId] else {
			Log.info("skipping refresh of unloaded preview", .app)
			return
		}
		// create code handler for this preview
		previewInfo.codeHandler = PreviewChunkCache(previewId: previewInfo.previewId, fileId: previewInfo.fileId, workspace: session.workspace, document: parserContext!.parsedDocument.value)
		currentPreview = previewInfo
		previewInfo.codeHandler.clearCache()
		refreshContent()
	}

	// MARK: - action handlers
	func executeChunk(number: Int, includePrevious: Bool) {
		guard let curPreview = currentPreview else { return }
		// invalidate future code chunks
		curPreview.codeHandler.willExecuteChunk(chunkIndex: number)
		_ = saveProducer?()
			.flatMap (.concat, {self.requestUpdate(previewId: curPreview.previewId, chunkId: number, includePrevious: includePrevious )})
			.startWithResult { result in
				switch result {
				case .failure(let error):
					Log.warn("preview update reuest failed: \(error)")
				case .success(_):
					// refresh tool
					let (indexes, enable) = curPreview.codeHandler.chunksValidity()
					let idxArray = indexes.map({ String($0) }).joined(separator: ", ")
					let enArray = enable.map({ String($0) }).joined(separator: ", ")
					self.runJavascript("adjustToolbarButtons([\(idxArray)], [\(enArray)]")
				}
			}
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

	/// parses the document and loads each chunk individually via javascript
	// swiftlint:disable:next cyclomatic_complexity
	private func updatePreview(updatedContents: String? = nil, forceParse: Bool = false) {
		guard didLoadView else { return }

		// handle empty content
		guard let curDoc = parsedDocument, let curPreview = currentPreview else { return; }
		if docHtmlLoaded, updatedContents == nil, !forceParse, curDoc.attributedString.length > 0 { return }
		guard let contents = updatedContents ?? parserContext?.parsedDocument.value?.rawString
			else { Log.warn("current doc has no contents??"); return }
		guard forceParse || curDoc.attributedString.string != updatedContents else { return }
		// update the parsed document, update the webview
		var changedChunkIndexes = [Int]()
		do {
			changedChunkIndexes = try RmdDocument.update(document: curDoc, with: contents) ?? []
		} catch {
			Log.warn("error parsing document: \(error)", .app)
			return
		}
		// add to changedChunkIndexes any chunks that need to udpated because of changes to R code
		if changedChunkIndexes.count > 0 {
			curPreview.codeHandler.cacheCode(changedChunks: &changedChunkIndexes)
		} else {
			curPreview.codeHandler.cacheAllCode()
		}
		// handle changes
		if !forceParse, changedChunkIndexes.count > 0 {
			Log.info("udpating just chunks \(changedChunkIndexes)")
			for chunkNumber in changedChunkIndexes {
				updateChunkByJS(chunkNumber: chunkNumber, document: curDoc)
			}
			runJavascript("updateSectionToolbars()")
		} else { // no changes, so just refresh everything
			refreshContent()
		}
	}

	/// actually cache code, generate html, insert via javascript
	private func refreshContent() {
		guard let curDoc = parsedDocument, currentPreview != nil else {
			load(html: "")
			return
		}
		if !(currentPreview?.codeHandler.contentCached ?? false) {
			currentPreview?.codeHandler.cacheAllCode()
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
		guard let codeHandler = currentPreview?.codeHandler else { fatalError("hgmlWrapper() called without a current preview") }
		html += codeHandler.htmlFor(chunk: chunk, index: chunkNumber)
		if !chunk.isInline {
			html += "\n</sectionContent>\n"
		}
		html += "\n</\(descriptor)>\n"
		return html
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
		Log.info("adding js to opQueue")
		opQueue.addOperation { [weak self] in
			guard let me = self else { return }
			let sema = DispatchSemaphore(value: 1)
			let encoded = script.data(using: .utf8)!.base64EncodedString()
			let realString = "executeScript(" + "`" + encoded + "`)"
			DispatchQueue.main.async {
				me.outputView?.evaluateJavaScript(realString) { (val, err) in
					if let error = err {
						Log.info("js returned error: \(error) ")
						Log.info("from \(realString)")
					}
					completionHandler?(val, err)
					sema.signal()
				}
				sema.wait()
			}
		}
	}

	// MARK: - Preview
	
	func updatePreview() {
		 // called when the entire preview should be updated
		updatePreview(updatedContents: nil, forceParse: true)
	}
	
	@discardableResult
	private func loadPreviewIfNecessary() -> Bool {
		guard !initialCodeLoaded, let fileId = editorContext.value?.currentDocument.value?.file.fileId else { return false }
		// TODO: needs to update appStatus
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
//					me.initialCodeLoaded = false
					me.refreshContent()
				}
			}
		}
		return true
	}

	/// caller is responsible for refreshing the content when a previewId is returned
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
					let codeHandler = PreviewChunkCache(previewId: previewId,  fileId: fileId, workspace: me.session.workspace, document: me.parserContext!.parsedDocument.value)
					let cacheEntry = PreviewIdCache(previewId: previewId, fileId: fileId, codeHandler: codeHandler)
					me.previewData[previewId] = cacheEntry
					me.currentPreview = cacheEntry
					observer.send(value: previewId)
					observer.sendCompleted()
				case .failure(let err):
					Log.warn("requestPreviewId got error \(err)")
					observer.send(error: err)
				}
			}
		}
		return handler
	}

	private func requestUpdate(previewId: Int, chunkId: Int, includePrevious: Bool = false) -> SignalProducer<Void, Rc2Error> {
		guard var _ = previewData[previewId] else {
			let rerr = Rc2Error(type: .application, nested: PrecviewError.failedToUpdate, severity: .warning)
			Log.info("Failed to find preview \(previewId)", .app)
			return SignalProducer<Void, Rc2Error>(error: rerr)
		}
		let handler = SignalProducer<Void, Rc2Error> { [weak self] observer, _ in
			guard let me = self else { return }
			// chunkIds will include previous
			let producer = me.session.updatePreviewChunks(previewId: previewId, chunkId: chunkId, includePrevious: includePrevious, updateId: "preview \(previewId)")
			producer.startWithCompleted {
//				preview.updateObserver = nil
			}
			
		}
		return handler
	}
	
	// MARK: - utility

	/// actually gets the updated html for chunkId and inserts via javascript
	private func updateChunkByJS(chunkNumber: Int, document: RmdDocument) {
		guard let codeHandler = currentPreview?.codeHandler else { fatalError("htmlFor(chunk:index:) called without a current preview") }
		let chunk = document.chunks[chunkNumber]
		
		var html = codeHandler.htmlFor(chunk: chunk, index: chunkNumber) // don't want the wrapping section ala htmlWrapper()
		if chunk.chunkType != .equation {
			html = escapeForJavascript(html)
		}
		
		var command = "$(\"sectioncontent[index='\(chunkNumber)']\").html('\(html)');"
		if chunk.chunkType == .equation {
			command += "MathJax.typeset()"
		}
		// TODO: catch javascript error to supply details
		runJavascript(command) { (_, err) in
			guard err == nil else {
				Log.warn("javascript failed", .app)
				return
			}
			Log.info("javascript worked")
		}
	}
	
	func setEditorContext(_ econtext: EditorContext?) {
		precondition(editorContext.value == nil)
		editorContext.value = econtext
		// if the editor doc changed, we need to note that
		curEditorDocDisposable = econtext?.currentDocument.signal.observeValues({ (newDoc) in
			self.initialCodeLoaded = false
		})
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
		webConfig?.userContentController.add(self, name: "error")
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
					executeChunk(number: chunkNum, includePrevious: false)
				case "executePrevious":
						executeChunk(number: chunkNum, includePrevious: true)
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
			Log.warn("skipping previewHandler message")
		} else {
			Log.info("unknown message posted from preview")
		}
	}

	// MARK: - embedded types

}

/// used to cache previews so old ones can be removed to free memory pressure
private struct PreviewIdCache: Equatable {
	init(previewId: Int, fileId: Int, codeHandler: PreviewChunkCache) {
		self.previewId = previewId
		self.fileId = fileId
		self.codeHandler = codeHandler
//		self.updateObserver = nil
	}

	static func == (lhs: PreviewIdCache, rhs: PreviewIdCache) -> Bool {
		return lhs.fileId == rhs.fileId && lhs.previewId == rhs.previewId
	}

	let previewId: Int
	let fileId: Int
	var codeHandler: PreviewChunkCache
	var lastAccess: TimeInterval = Date.timeIntervalSinceReferenceDate
//	var updateObserver: Signal<Void, Rc2Error>.Observer?
}

// MARK: - SessionPreviewDelegate
extension LivePreviewDisplayController: SessionPreviewDelegate {
	func previewUpdateReceived(response: SessionResponse.PreviewUpdateData) {
		defer {
			if response.updateComplete {
				guard let fileId = editorContext.value?.currentDocument.value?.file.fileId
				else { fatalError("update complete with no current file") }
				NotificationCenter.default.postNotificationNameOnMainThread(.previewUpdateEnded, object: session, userInfo: ["fileId": fileId])
			}
		}
		//ignore updates that are just to mark completed
		guard response.chunkId >= 0 else {
			// last chunk, queue up display update after all chunks are updated
			opQueue.addOperation { [weak self] in
				DispatchQueue.main.async {
					self?.updatePreview()
				}
			}
			return
		}
		guard var preview = previewData[response.previewId] else { return }
		// update the code results
		preview.codeHandler.updateCodeOutput(chunkNumber: response.chunkId, outputContent: response.results)
		// rebuild the entire output for the chunk
		let html = preview.codeHandler.htmlForCodeChunk(chunkNumber: response.chunkId)
		preview.lastAccess = Date.timeIntervalSinceReferenceDate
		let script = """
		$("sectionContent[index=\(response.chunkId)] > .codeChunk").replaceWith(`\(html)`)
		"""
		runJavascript(script)
	}
	
	func previewUpdateStarted(response: SessionResponse.PreviewUpdateStartedData) {
		guard let preview = previewData[response.previewId] else { return }
		preview.codeHandler.cacheAllCode()
		guard let fileId = editorContext.value?.currentDocument.value?.file.fileId
		else { fatalError("preview started with no editor context") }
		NotificationCenter.default.postNotificationNameOnMainThread(.previewUpdateStarted, object: session, userInfo: ["fileId": fileId])
	}
}
