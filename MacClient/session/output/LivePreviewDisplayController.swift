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
	///   - contents: the propsed updated contents
	///   - range: the range of the text in the original string
	///   - delta: the change made
	/// - Returns: true if the changes should be saved to the current document's editedContents causing a reparse
	func contentsEdited(contents: String, range: NSRange, delta: Int) -> Bool
}

class LivePreviewDisplayController: AbstractSessionViewController, OutputController, LivePreviewOutputController, WKUIDelegate, WKNavigationDelegate
{
	var contextualMenuDelegate: ContextualMenuDelegate?
	var sessionController: SessionController?
	private var parsedDocument: RmdDocument? = nil
	private var context: MutableProperty<EditorContext?> = MutableProperty<EditorContext?>(nil)
	private var curDocDisposable: Disposable?
	private var contentsDisposable: Disposable?
	private var lastContents: String?
	private var lineContiuationRegex: NSRegularExpression!
	private var openDoubleDollarRegex: NSRegularExpression!
	private var closeDoubleDollarRegex: NSRegularExpression!
	private var documentRoot: URL?
	private var resourcesExtracted = false
	private var parseInProgress = false
	private var emptyNavigations: Set<WKNavigation> = []
	private var headerContents = ""
	private var footerContents = ""
	private var didLoadView = false
	
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
		contentsDisposable?.dispose()
		contentsDisposable = context.value?.currentDocument.value?.editedContents.signal.observeValues { [weak self] _ in
			self?.contentsChanged()
		}
		updatePreview()
	}
	
	/// called when the editedContexts of the current document changed
	private func contentsChanged() {
//		updatePreview()
	}
	
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

	/// called when the context property has been set
	private func contextChanged() {
		lastContents = nil
		parsedDocument = nil
		curDocDisposable?.dispose()
		curDocDisposable = nil
		contentsDisposable?.dispose()
		contentsDisposable = nil
		curDocDisposable = editorContext?.currentDocument.signal.observeValues({ [weak self] newDoc in
			self?.documentChanged()
		})
		if !resourcesExtracted {
			ensureResourcesLoaded()
		}
		documentChanged()
	}
	
	/// parses the parsed document and loads it via javascript
	private func updatePreview(updatedContents: String? = nil) {
		guard !parseInProgress else { return }
		guard didLoadView else { return }
		var updateParse = true
		var clearLastContents = false
		defer { if clearLastContents { self.lastContents = nil} }
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
		guard let curDoc = parsedDocument else {
			load(html: emptyContents)
			return
		}
		guard let contents = updatedContents ?? context.value?.currentDocument.value?.currentContents
			else { Log.warn("current doc has no contents??"); return }
		if contents == lastContents { return }
		parseInProgress = true
		defer { parseInProgress = false }
		let changedChunkIndexes = try! RmdDocument.update(document: curDoc, with: contents) ?? []
		if changedChunkIndexes.count > 0 {
			Log.info("udpating just chunks \(changedChunkIndexes)")
			for chunkNumber in changedChunkIndexes {
				let chunk = curDoc.chunks[chunkNumber]
				let html = escapeForJavascript(htmlFor(chunk: chunk))
				let command = "$(\"section[index='\(chunkNumber)']\").html('\(html)'); MathJax.typeset()"
				outputView?.evaluateJavaScript(command, completionHandler: nil)
			}
		} else {
			var html =  ""
			for (chunkNumber, chunk) in curDoc.chunks.enumerated() {
				html += "<section index=\"\(chunkNumber)\">\n"
				html += htmlFor(chunk: chunk)
				html += "\n</section>\n"
			}
			load(html: "\(headerContents)\n\(html)\n\(footerContents)")
		}
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
		let allChunks = chunk.inlineElements
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
	
	/// replaces the visible html document
	/// - Parameter html: the new html to display
	private func load(html: String)  {
		let nav = outputView?.loadHTMLString(html, baseURL: documentRoot)
		if let realNav = nav { emptyNavigations.insert(realNav) }
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
		guard didLoadView else { return }
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
}
