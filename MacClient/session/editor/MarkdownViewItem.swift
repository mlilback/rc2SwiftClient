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

	override func viewDidLoad() {
		super.viewDidLoad()
		sourceView.isEditable = true
		view.translatesAutoresizingMaskIntoConstraints = false
		topView.layer?.backgroundColor = notebookTopViewBackgroundColor.cgColor
	}

	override func prepareForReuse() {
		super.prepareForReuse()
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
		guard data != nil else { return }
		// Sets each view's string from the data's string
		guard let sourceStorage = sourceView?.textStorage else { fatalError() }
		if let attrStr = data?.chunk.attributedContents {
			sourceStorage.replaceCharacters(in: sourceStorage.string.fullNSRange, with: attrStr)
		} else {
			sourceView.replace(text: data?.source.string ?? "")
		}
	}
	
	func size(forWidth width: CGFloat) -> NSSize {
		let tmpSize = NSSize(width: width, height: 100)
		sourceView.setFrameSize(tmpSize)
		guard let manager = sourceView.textContainer?.layoutManager, let container = sourceView.textContainer else { return .zero }
		manager.ensureLayout(for: container)
		let textSize = manager.usedRect(for: container).size
		return NSSize(width: width, height: textSize.height + topView.frame.size.height)
	}
}

class MarkdownTextView: NSTextView {
	// use the space necessary for contents as intrinsic content size
	override var intrinsicContentSize: NSSize {
		guard let manager = textContainer?.layoutManager, let container = textContainer else { return .zero }
		manager.ensureLayout(for: container)
		return manager.usedRect(for: container).size
	}
}
