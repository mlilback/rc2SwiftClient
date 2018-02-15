//
//  Searchable.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol Searchable {
	func performFind(action: NSTextFinder.Action)
	var supportsSearchBar: Bool { get }
	var searchBarVisible: Bool { get }
	var searchableTextView: NSTextView? { get }
}

extension Searchable {
	func performFind(action: NSTextFinder.Action) {
		if let textView = searchableTextView {
			let menuItem = NSMenuItem(title: "foo", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
			menuItem.tag = action.rawValue
			textView.performFindPanelAction(menuItem)
			if action == .hideFindInterface {
				textView.enclosingScrollView?.isFindBarVisible = false
			}
		}
	}
	var supportsSearchBar: Bool { return false }
	var searchBarVisible: Bool { return searchableTextView?.enclosingScrollView?.isFindBarVisible ?? false }
	var searchableTextView: NSTextView? { return nil }
}
