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

protocol NotebookViewItem: class {
	var delegate: NotebookViewItemDelegate? { get set }
	var data: NotebookItemData? { get set }
	var context: EditorContext? { get set }
}

