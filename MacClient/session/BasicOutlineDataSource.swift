//
//  BasicOutlineDataSource.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class BasicOutlineDataSource<T: AnyObject>: NSObject, NSOutlineViewDataSource {
	typealias OutlineViewFactory = (T) -> NSView

	var data: [T]
	var viewFactory: OutlineViewFactory
	var childAccessor: (T) -> [T]?

	init(data: [T], childAccessor:@escaping (T) -> [T]?, viewFactory:@escaping OutlineViewFactory) {
		self.data = data
		self.viewFactory = viewFactory
		self.childAccessor = childAccessor
		super.init()
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let topic = item as? T {
			return childAccessor(topic)?.count ?? 0
		}
		return data.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if nil == item { return data[index] }
		return childAccessor(item as! T)![index] // swiftlint:disable:this force_cast
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		if let topic = item as? T, let topics = childAccessor(topic) {
			return topics.count > 0
		}
		return false
	}

	public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		return viewFactory(item as! T) // swiftlint:disable:this force_cast
	}

}
