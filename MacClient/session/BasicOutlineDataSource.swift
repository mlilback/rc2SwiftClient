//
//  BasicOutlineDataSource.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class BasicOutlineDataSource<T: AnyObject>: NSObject, NSOutlineViewDataSource {
	typealias OutlineViewFactory = (T) -> NSView
	
	var data:[T]
	var viewFactory: OutlineViewFactory
	var childAccessor: (T) -> [T]?
	
	init(data:[T], childAccessor:(T) -> [T]?, viewFactory:OutlineViewFactory) {
		self.data = data
		self.viewFactory = viewFactory
		self.childAccessor = childAccessor
		super.init()
	}
	
	func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
		if let topic = item as? T {
			return childAccessor(topic)?.count ?? 0
		}
		return data.count
	}
	
	func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
		if nil === item { return data[index] }
		return childAccessor(item as! T)![index]
	}
	
	func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
		if let topic = item as? T, let topics = childAccessor(topic) {
			return topics.count > 0
		}
		return false
	}
	
	func outlineView(outlineView: NSOutlineView, viewForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
		return viewFactory(item as! T)
	}

}
