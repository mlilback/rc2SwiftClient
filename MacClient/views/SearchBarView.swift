//
//  SearchBarView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

public protocol SearchBarViewDelegate: class {
	func goForward(searchBar: SearchBarView)
	func goBackward(searchBar: SearchBarView)
	func dismiss(searchBar: SearchBarView)
	func performSearch(searchBar: SearchBarView, string: String)
}

enum SearchOptionTags: Int {
	case invalid = -1
	case wholeWords = 50
	case caseSensitive
}

@IBDesignable
public class SearchBarView: NSView {
	private var topLevelView: NSView?
	@IBOutlet var searchField: NSSearchField?
	@IBOutlet var doneButton: NSButton?
	@IBOutlet var backForwardButtons: NSSegmentedControl?
	@IBInspectable var bgColor: NSColor?
	public weak var delegate: SearchBarViewDelegate?
	
	var searchString: String {
		get { return searchField?.stringValue ?? "" }
		set { searchField?.stringValue = newValue }
	}
	var wholeWordsOption: Bool = true
	var caseSensitiveOption: Bool = false
	
	/// setting the matchCount resets the search currentMatchIndex to 0 and updates the UI
	public var matchCount: Int = 0 { didSet { currentMatchIndex = 0; adjustInterface() } }
	public private(set) var currentMatchIndex: Int = 0
	
	public override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}
	
	required public init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	public override func awakeAfter(using aDecoder: NSCoder) -> Any? {
		var topObjects: NSArray? = NSArray()
		self.translatesAutoresizingMaskIntoConstraints = false
		guard Bundle(for: type(of: self)).loadNibNamed(NSNib.Name(rawValue: "SearchBarView"), owner: self, topLevelObjects: &topObjects), let fetchedTopObjects = topObjects else { fatalError("failed to load search xib") }
		self.topLevelView = fetchedTopObjects.first(where: { $0 is NSView }) as? NSView
		topLevelView?.translatesAutoresizingMaskIntoConstraints = false
		self.addSubview(self.topLevelView!)
		self.addConstraint(leadingAnchor.constraint(equalTo: topLevelView!.leadingAnchor))
		self.addConstraint(trailingAnchor.constraint(equalTo: topLevelView!.trailingAnchor))
		self.addConstraint(topAnchor.constraint(equalTo: topLevelView!.topAnchor))
		self.addConstraint(bottomAnchor.constraint(equalTo: topLevelView!.bottomAnchor))
		return self
	}
	
	override public func awakeFromNib() {
		super.awakeFromNib()
	}
	
	/// action for the search button
	@IBAction func doSearch(_ sender: Any?) {
		delegate?.performSearch(searchBar: self, string: self.searchString)
	}

	/// action for the next/previous segmented control
	@IBAction func doNavigation(_ sender: Any?) {
		if backForwardButtons?.selectedSegment == 0 {
			delegate?.goBackward(searchBar: self)
		} else if backForwardButtons?.selectedSegment == 1 {
			delegate?.goForward(searchBar: self)
		}
	}

	/// action for the done button
	@IBAction func doDone(_ sender: Any?) {
		delegate?.dismiss(searchBar: self)
	}
	
	/// menu action for whole word search option
	@IBAction func toggleWholeWords(_ sender: Any) {
		guard let menuItem = sender as? NSMenuItem else { return }
		wholeWordsOption = menuItem.state == .onState
	}

	/// menu action for teh case sensitive search option
	@IBAction func toggleCaseInsensitive(_ sender: Any) {
		guard let menuItem = sender as? NSMenuItem else { return }
		caseSensitiveOption = menuItem.state == .onState
	}
	
	/// updates controls to match current result state
	func adjustInterface() {
		let navEnabled = matchCount > 0
		backForwardButtons?.setEnabled(navEnabled, forSegment: 0)
		backForwardButtons?.setEnabled(navEnabled, forSegment: 1)
	}
}

extension SearchBarView: NSMenuDelegate {
	override public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		var enable = false
		if menuItem.tag == SearchOptionTags.caseSensitive.rawValue {
			menuItem.state = caseSensitiveOption ? .onState : .offState
			enable = true
		} else if menuItem.tag == SearchOptionTags.wholeWords.rawValue {
			menuItem.state = wholeWordsOption ? .onState : .offState
			enable = true
		}
		return enable
	}
}
