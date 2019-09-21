//
//  WebViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import WebKit
import MJLLogger

class WebViewController: AbstractSessionViewController, OutputController, WKNavigationDelegate, ContextualMenuDelegate {
	var webView: Rc2WebView?
	@IBOutlet var containerView: NSView?
	@IBOutlet var navButtons: NSSegmentedControl?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var titleLabel: NSTextField?
	@IBOutlet var searchBar: SearchBarView?
	@IBOutlet var searchBarHeightConstraint: NSLayoutConstraint?
	
	weak var contextualMenuDelegate: ContextualMenuDelegate?
	
	var webConfig: WKWebViewConfiguration?
	fileprivate var searchBarHeight: CGFloat = 0
	var supportsSearchBar: Bool { return true }
	var searchBarVisible: Bool { return (searchBarHeightConstraint?.constant ?? 0 > 0) }
	
	open var pageTitle: String { return webView?.title ?? "" }
	
	// MARK: - methods
	override open func viewDidLoad() {
		super.viewDidLoad()
		let prefs = WKPreferences()
		prefs.minimumFontSize = 9.0
		prefs.javaEnabled = false
		prefs.javaScriptCanOpenWindowsAutomatically = false
		let config = WKWebViewConfiguration()
		config.preferences = prefs
		config.applicationNameForUserAgent = "Rc2"
		config.allowsAirPlayForMediaPlayback = true
		webConfig = config
		setupWebView()
		titleLabel?.stringValue = ""
		searchBarHeight = searchBarHeightConstraint?.constant ?? 0
		searchBarHeightConstraint?.constant = 0
		searchBar?.delegate = self
		loadScript(filename: "jquery.min", fileExtension: "js")
		loadScript(filename: "jquery.mark.min", fileExtension: "js")
		loadScript(filename: "rc2search", fileExtension: "js")
	}
	
	func setupWebView() {
		webView?.removeFromSuperview()
		webView = Rc2WebView(frame: view.frame.insetBy(dx: 4, dy: 4), configuration: webConfig!)
		webView?.navigationDelegate = self
		webView?.translatesAutoresizingMaskIntoConstraints = false
		containerView?.addSubview(webView!)
		webView!.topAnchor.constraint(equalTo: (containerView?.topAnchor)!).isActive = true
		webView!.bottomAnchor.constraint(equalTo: (containerView?.bottomAnchor)!).isActive = true
		webView!.leadingAnchor.constraint(equalTo: (containerView?.leadingAnchor)!).isActive = true
		webView!.trailingAnchor.constraint(equalTo: (containerView?.trailingAnchor)!).isActive = true
		webView!.contextualMenuDelegate = self
	}
	
	func loadScript(filename: String, fileExtension: String) {
		let url = Bundle.main.url(forResource: filename, withExtension: fileExtension, subdirectory: "static_html")!
		guard let srcStr = try? String(contentsOf: url) else { return }
		let script = WKUserScript(source: srcStr, injectionTime: .atDocumentStart, forMainFrameOnly: true)
		webConfig?.userContentController.addUserScript(script)
	}
	
	func currentPageSearchable() -> Bool {
		return webView?.url != nil
	}
	
	@IBAction func navigateWebView(_ sender: AnyObject) {
		switch (navButtons?.selectedSegment)! {
		case 0:
			webView?.goBack(sender)
		case 1:
			webView?.goForward(sender)
		default:
			break
		}
	}
	
	@IBAction func showShareSheet(_ sender: AnyObject) {
		let sharepicker = NSSharingServicePicker(items: [webView!.url!])
		sharepicker.show(relativeTo: (shareButton?.frame)!, of: (shareButton?.superview)!, preferredEdge: .maxY)
	}

	open func staticHmtlFolder() -> URL {
		let pkg = Bundle(for: type(of: self))
		let url = pkg.url(forResource: "help404", withExtension: "html", subdirectory: "static_html")
		return url!.deletingLastPathComponent()
	}

	open func insert(css: String, into webView: WKWebView) {
		let jsString = "var style = document.createElement('style'); style.innerHTML='\(css)'; document.head.appendChild(style);"
		webView.evaluateJavaScript(jsString, completionHandler: nil)
	}
	
	//MARK -- WKNavigationDelegate
	
	open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
	{
		navButtons?.setEnabled(webView.canGoBack, forSegment: 0)
		navButtons?.setEnabled(webView.canGoForward, forSegment: 1)
		titleLabel?.stringValue = pageTitle
	}
	
	open func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Log.error("failed to navigate: \(error)", .app)
	}
	
	open func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
	}
	
	open func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error)
	{
		Log.error("failed to provisionally navigate: \(error)", .app)
	}
}

extension WebViewController: SearchBarViewDelegate {
	public func goForward(searchBar: SearchBarView) {
		webView?.evaluateJavaScript("cycleMatch(1)")
	}

	public func goBackward(searchBar: SearchBarView) {
		webView?.evaluateJavaScript("cycleMatch(-1)")
	}
	
	public func dismiss(searchBar: SearchBarView) {
		hideSearchBar()
	}
	
	//internal choke point for hiding searchbar
	fileprivate func hideSearchBar() {
		searchBarHeightConstraint?.constant = 0
		webView?.evaluateJavaScript("clearSearch()")
	}
	
	private struct SearchParams: Codable {
		let term: String
		let options: [String:String] = [:]
	}
	
	public func performSearch(searchBar: SearchBarView, string: String) {
		let encoder = JSONEncoder()
		let params = SearchParams(term: string)
		do {
			let data = try encoder.encode(params)
			let encoded = data.base64EncodedString()
			let script = "doSearch('\(encoded)')"
			webView?.evaluateJavaScript(script) { (value, _) in
				guard let matchCount = value as? Int, matchCount >= 0 else {
					Log.warn("invalid value returned from javascript search", .app)
					return
				}
				searchBar.matchCount = matchCount
			}
		} catch {
			Log.warn("error encoding java script search: \(error)", .app)
		}
	}
	
	func contextMenuItems(for controller: OutputController) -> [NSMenuItem] {
		return contextualMenuDelegate?.contextMenuItems(for: controller) ?? []
	}
}

extension WebViewController: Searchable {
	func performFind(action: NSTextFinder.Action) {
		guard currentPageSearchable() else { return }
		switch action {
		case .showFindInterface:
			searchBarHeightConstraint?.constant = searchBarHeight
			view.window?.makeFirstResponder(searchBar?.searchField)
		case .hideFindInterface:
			hideSearchBar()
		default:
			break
		}
	}
}

// MARK: -

class Rc2WebView: WKWebView, OutputController {
	private var menuItemsAdded: Int = 0
	weak var contextualMenuDelegate: ContextualMenuDelegate?
	
	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		let items = contextualMenuDelegate!.contextMenuItems(for: self)
		for (index, item) in items.enumerated() {
			menu.insertItem(item, at: index)
		}
		menuItemsAdded = items.count
		if menuItemsAdded > 0 {
			menuItemsAdded += 1
			menu.insertItem(NSMenuItem.separator(), at: items.count)
		}
	}
	
	override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
		for _ in 0..<menuItemsAdded {
			menu.removeItem(at: 0)
		}
	}
}
