//
//  MarkdownViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SyntaxParsing
import ReactiveSwift

class MarkdownViewItem: NotebookViewItem {
	// MARK: properties
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var scrollView: NSScrollView!
	@IBOutlet weak var chunkTypeLabel: NSTextField!
	@IBOutlet weak var addChunkButton: NSButton!
	
	private var fontDisposable: Disposable?
	private var boundsToken: Any?
	private var sizingTextView: NSTextView?
	private var ignoreTextChanges = false

	// MARK: methods
	override func viewDidLoad() {
		super.viewDidLoad()
		sourceView.isEditable = true
		sourceView.delegate = self
		view.translatesAutoresizingMaskIntoConstraints = false
		sourceView.changeCallback = { [weak self] in
			self?.collectionView?.collectionViewLayout?.invalidateLayout()
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		sourceView.textStorage?.replace(with: "")
	}

	@IBAction func addChunk(_ sender: Any?) {
		delegate?.addChunk(after: self, sender: sender as? NSButton)
	}

	override func contextChanged() {
		fontDisposable?.dispose()
		fontDisposable = context?.editorFont.signal.observeValues { [weak self] font in
			self?.sourceView.font = font
		}
		guard let context = context else { return }
		sourceView.font = context.editorFont.value
	}
	
	private func changeTo(storage: NSTextStorage) {
		sourceView.layoutManager?.replaceTextStorage(storage)
	}
	
	override func dataChanged() {
		boundsToken = nil
		guard let data = data else { return }
		boundsToken = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sourceView, queue: .main)
		{ [weak self] note in
			self?.collectionView?.collectionViewLayout?.invalidateLayout()
		}
		// use the data's text storage
		sourceView.textStorage?.replace(with: data.source)
	}
	
	func size(forWidth width: CGFloat) -> NSSize {
		let tmpSize = NSSize(width: width, height: 100)
		sourceView.setFrameSize(tmpSize)
		guard let manager = sourceView.textContainer?.layoutManager, let container = sourceView.textContainer else { return .zero }
		manager.ensureLayout(for: container)
		let textSize = manager.usedRect(for: container).size
		return NSSize(width: width, height: textSize.height + topView.frame.size.height + Notebook.textEditorMargin)
	}

	override func size(forWidth width: CGFloat, data: NotebookItemData) -> NSSize {
		if nil == sizingTextView {
			sizingTextView = NSTextView(frame: CGRect(x: 0, y: 0, width: width, height: 100))
		}
		let tmpSize = NSSize(width: width, height: 100)
		sizingTextView?.setFrameSize(tmpSize)
		sizingTextView?.textStorage?.replaceCharacters(in: sizingTextView!.string.fullNSRange, with: data.source)
		guard let manager = sizingTextView?.textContainer?.layoutManager, let container = sizingTextView?.textContainer else { return .zero }
		manager.ensureLayout(for: container)
		let textSize = manager.usedRect(for: container).size
		return NSSize(width: width, height: textSize.height + topView.frame.size.height + Notebook.textEditorMargin)
	}
}

extension MarkdownViewItem: NSTextViewDelegate {
	func textShouldEndEditing(_ textObject: NSText) -> Bool {
		guard !ignoreTextChanges else { return true }
		ignoreTextChanges = true
		defer { ignoreTextChanges = false }
		data?.source = sourceView.textStorage!
		delegate?.viewItemLostFocus()
		return true
	}

	func textDidChange(_ notification: Notification) {
		guard let textView = notification.object as? MarkdownTextView else { return }
		data?.source = sourceView.textStorage!
		textView.invalidateIntrinsicContentSize()
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
