//
//  NotebookViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

protocol NotebookViewItemDelegate: class {
	func addChunk(after: NotebookViewItem, sender: NSButton?)
	/// should call .resultsVisible = hide on all chunks
	func twiddleAllChunks(hide: Bool)
}

class NotebookViewItem: NSCollectionViewItem {
	@IBOutlet var topView: NSView!
	
	weak var delegate: NotebookViewItemDelegate?
	var data: NotebookItemData? { didSet { dataChanged() } }
	var context: EditorContext? { didSet { contextChanged() } }
	
	override var isSelected: Bool { didSet { selectionChanged() } }
	
	override func viewDidLoad() {
		super.viewDidLoad()
		view.wantsLayer = true
		view.layer?.borderWidth = notebookItemBorderWidth
		view.layer?.borderColor = notebookBorderColor.cgColor
		topView?.wantsLayer = true
		topView.layer?.backgroundColor = notebookTopViewBackgroundColor.cgColor
		NotificationCenter.default.addObserver(self, selector: #selector(firstResponderChanged), name: .firstResponderChanged, object: nil)
	}
	
	/// called when the isSelected property changes. overrides must call super!
	func selectionChanged() {
		guard isViewLoaded else { return }
		let bgcolor = isSelected ? notebookSelectionColor : notebookTopViewBackgroundColor
		topView.layer?.backgroundColor = bgcolor.cgColor
		view.layer?.borderColor = isSelected ? notebookSelectionColor.cgColor : notebookBorderColor.cgColor
		view.layer?.borderWidth = isSelected ? notebookSelectionBorderWidth : notebookItemBorderWidth
	}
	
	/// called when the first responder has changed. Has collectionView make this item the selection if the first responder is a descendent
	@objc func firstResponderChanged() {
		guard let fresponder = view.window?.firstResponder as? NSView else { return }
		guard fresponder.isDescendant(of: view), let myPath = collectionView?.indexPath(for: self) else { return }
		collectionView?.selectionIndexPaths = Set([myPath])
	}
	
	/// called when the context value has changed
	func contextChanged() { }
	
	/// called when the data item has changed
	func dataChanged() { }
	
	func size(forWidth width: CGFloat, data: NotebookItemData) -> NSSize {
		fatalError("not implemented")
	}
}

