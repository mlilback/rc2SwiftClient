//
//  MarkdownViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SyntaxParsing
import MJLLogger
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
	private var originalContents: String?
	
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
		originalContents = nil
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
	
	override func dataChanged() {
		boundsToken = nil
		guard let data = data else { return }
		boundsToken = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sourceView, queue: .main)
		{ [weak self] note in
			self?.collectionView?.collectionViewLayout?.invalidateLayout()
		}
		originalContents = data.source.string
		// use the data's text storage
		sourceView.textStorage?.replace(with: data.source)
		sourceView.textStorage!.enumerateAttribute(.attachment, in: sourceView.string.fullNSRange, options: []) { (aValue, aRange, stop) in
			guard let attach = aValue as? InlineAttachment else { return }
			guard let cell = attach.attachmentCell as? NSTextAttachmentCell else { return }
			guard let chunk = attach.chunk else { return }
			// eventually need to support code chunks, too
			guard chunk is Equation else { return }
			if let eqImage = context?.inlineImageFor(latex: chunk.contents.string) {
				cell.image = eqImage
			}
		}
		sourceView.textStorage?.addAttribute(.font, value: context?.editorFont.value as Any, range: sourceView.textStorage!.string.fullNSRange)
	}
	
	override func saveIfDirty() {
		guard !ignoreTextChanges else { return }
		ignoreTextChanges = true
		defer { ignoreTextChanges = false}
		data?.source = sourceView.textStorage!
		originalContents = sourceView.string
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
	
	func textView(_ textView: NSTextView, clickedOn cell: NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int)
	{
		guard let attach = cell.attachment as? InlineAttachment, let ichunk = attach.chunk
			else { Log.warn("unknown attachment type clicked"); return }
		delegate?.presentInlineEditor(chunk: ichunk, parentItem: self, sourceView: textView, positioningRect: cellFrame)
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
