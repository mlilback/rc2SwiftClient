//
//  MarkdownViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SyntaxParsing
import ReactiveSwift

class MarkdownViewItem: NSCollectionViewItem, NotebookViewItem, NSTextViewDelegate {
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var scrollView: NSScrollView!
	@IBOutlet weak var topView: NSView!
	@IBOutlet weak var chunkTypeLabel: NSTextField!
	@IBOutlet weak var addChunkButton: NSButton!
	
	weak var delegate: NotebookViewItemDelegate?
	var data: NotebookItemData? { didSet { dataChanged() } }
	var context: EditorContext? { didSet { contextChanged() } }
	private var fontDisposable: Disposable?
	private var boundsToken: Any?

	override func viewDidLoad() {
		super.viewDidLoad()
		sourceView.isEditable = true
		view.translatesAutoresizingMaskIntoConstraints = false
		topView.layer?.backgroundColor = notebookTopViewBackgroundColor.cgColor
		sourceView.changeCallback = { [weak self] in
			self?.collectionView?.collectionViewLayout?.invalidateLayout()
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		sourceView.layoutManager?.replaceTextStorage(NSTextStorage())
	}

	@IBAction func addChunk(_ sender: Any?) {
		delegate?.addChunk(after: self, sender: sender as? NSButton)
	}

	func textDidChange(_ notification: Notification) {
		guard let textView = notification.object as? MarkdownTextView else { return }
		textView.invalidateIntrinsicContentSize()
	}

	private func contextChanged() {
		fontDisposable?.dispose()
		fontDisposable = context?.editorFont.signal.observeValues { [weak self] font in
			self?.data?.source.font = font
			self?.sourceView.font = font
		}
		guard let context = context else { return }
		data?.source.font = context.editorFont.value
		sourceView.font = context.editorFont.value
	}
	
	func dataChanged() {
		boundsToken = nil
		guard let data = data else { return }
		boundsToken = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sourceView, queue: .main)
		{ [weak self] note in
			self?.collectionView?.collectionViewLayout?.invalidateLayout()
		}
		// use the data's text storage
		sourceView.layoutManager?.replaceTextStorage(data.source)
	}
	
	func size(forWidth width: CGFloat) -> NSSize {
		let tmpSize = NSSize(width: width, height: 100)
		sourceView.setFrameSize(tmpSize)
		guard let manager = sourceView.textContainer?.layoutManager, let container = sourceView.textContainer else { return .zero }
		manager.ensureLayout(for: container)
		let textSize = manager.usedRect(for: container).size
		return NSSize(width: width, height: textSize.height + topView.frame.size.height + Notebook.textEditorMargin)
	}
}

class MarkdownTextView: SourceTextView {
	// use the space necessary for contents as intrinsic content size
	override var intrinsicContentSize: NSSize {
		guard let manager = textContainer?.layoutManager, let container = textContainer else { return .zero }
		manager.ensureLayout(for: container)
		return manager.usedRect(for: container).size
	}
}
