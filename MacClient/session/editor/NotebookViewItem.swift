//
//  NotebookViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol NotebookViewItemDelegate: class {
	func addChunk(after: NotebookViewItem, sender: NSButton?)
	/// should call .resultsVisible = hide on all chunks
	func twiddleAllChunks(hide: Bool)
}

class NotebookViewItem: NSCollectionViewItem {
	weak var delegate: NotebookViewItemDelegate?
	var data: NotebookItemData? { didSet { dataChanged() } }
	var context: EditorContext? { didSet { contextChanged() } }
	
	/// called when the context value has changed
	func contextChanged() { }
	
	/// called when the data item has changed
	func dataChanged() { }
	
	func size(forWidth width: CGFloat, data: NotebookItemData) -> NSSize {
		fatalError("not implemented")
	}
}

