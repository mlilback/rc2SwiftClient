//
//  NotebookViewItem.swift
//  Rc2Notebook
//
//  Created by Mark Lilback on 1/31/18.
//  Copyright © 2018 Mark Lilback. All rights reserved.
//

import Cocoa
import SyntaxParsing
import ReactiveSwift
import ReactiveCocoa
import MJLLogger

class ChunkViewItem: NotebookViewItem {
	let dividerBarHeight: CGFloat = 21
	let verticalMarginHeight: CGFloat = 10
	// MARK: - properties
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var resultTextView: SourceTextView?
	@IBOutlet weak var middleView: NSView?
	@IBOutlet weak var resultTwiddle: NSButton!
	@IBOutlet weak var chunkTypeLabel: NSTextField!
	@IBOutlet weak var addChunkButton: NSButton!
	@IBOutlet weak var optionsField: NSTextField!
	var layingOut = false
	private var twiddleInProgress = false
	private var optionsDisposable: Disposable?
	private var sizingTextView: NSTextView?
	
	/// if a subclass uses a non-NSTextView results view, this needs to be overridden to calculate frame
	var resultView: NSView { return resultTextView! }
	/// if the result view shown is in a scrollview, this is the scrollview. otherwise it is the result view.
	var resultOuterView: NSView { return resultView.enclosingScrollView ?? resultView }
	/// if results are text, figure out the frame needed to show the content. otherwise, using fixed size
	var dynamicContentFrame: CGRect { return resultTextView?.layoutManager!.usedRect(for: resultTextView!.textContainer!) ?? resultView.frame }
	
	private var fontDisposable: Disposable?
	private var resultVisibleDisposable: Disposable?

	// MARK: - standard
	deinit {
		fontDisposable?.dispose()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		sourceView.delegate = self
		
		// Get notified if view's bounds change:
		NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: sourceView)
		if resultTextView != nil {
			NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: resultView)
		}
		
		// Set background colors for top and middle views:
		middleView?.wantsLayer = true
		middleView?.layer?.backgroundColor = notebookMiddleBackgroundColor.cgColor
		resultView.layer?.backgroundColor = notebookMiddleBackgroundColor.cgColor
		// Note: results content background is set its .xib.
		sourceView.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
		//  Create a callback to adjustSize, so NotebookEntryView can call it during its layout:
		guard let myview = view as? NotebookEntryView else { fatalError() }
		myview.performLayout = { [weak self] in
			self?.adjustSize() }
	}
	
	// Recycle an unseen NotebookViewItem container for different visible data:
	override func prepareForReuse() {
		super.prepareForReuse()
		data = nil
		resultTextView?.textStorage?.replace(with: "")
		optionsDisposable?.dispose()
		optionsDisposable = nil
	}

	// MARK: - change handling
	// If the view size changes, re-adjust data height:
	@objc func boundsChanged(_ note: Notification) {
		adjustSize()
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
		resultVisibleDisposable?.dispose()
		guard let data = data else { return }
		// observe result visibility
		resultVisibleDisposable = data.resultsVisible.producer.startWithValues { [weak self] visible in
			self?.adjustResults(visible: visible)
		}
		// Callbacks from changes in NSTextViews that adjust the item view size:
		sourceView.changeCallback = { [weak self] in
			self?.adjustSize()
		}
		resultTextView?.changeCallback = { [weak self] in
			self?.adjustSize()
			Log.debug("resultView.changeCallback", .app)
		}
		// copy the source string
		sourceView.textStorage!.replace(with: data.source)
		// bind options field
		optionsDisposable?.dispose()
		if let codeChunk = data.chunk as? Code {
			optionsDisposable = optionsField.reactive.stringValue <~ codeChunk.options
		}
		//adjust label
		chunkTypeLabel.stringValue = titleForCurrentChunk()
		resultTwiddle.state = data.resultsVisible.value ? .on : .off
		adjustSize(animate: false)
	}

	// MARK: - sizing
	
	override func size(forWidth width: CGFloat, data: NotebookItemData) -> NSSize {
		if nil == sizingTextView {
			sizingTextView = NSTextView(frame: CGRect(x: 0, y: 0, width: width, height: 100))
		}
		guard let manager = sizingTextView?.textContainer?.layoutManager, let container = sizingTextView?.textContainer else { return .zero }
		let tmpSize = NSSize(width: width, height: 100)
		sizingTextView?.setFrameSize(tmpSize)
		sizingTextView?.textStorage?.replace(with: data.source)
		manager.ensureLayout(for: container)
		var workingSize = manager.usedRect(for: container).size
		workingSize.height += dividerBarHeight
		if middleView != nil {
			workingSize.height += dividerBarHeight
		}
		if data.resultsVisible.value {
			sizingTextView?.textStorage?.replace(with: data.result)
			manager.ensureLayout(for: container)
			workingSize.height += dynamicContentFrame.size.height
		}
		workingSize.height += Notebook.textEditorMargin
		workingSize.height += topView.frame.size.height
		return workingSize
//		return NSSize(width: width, height: sourceSize.height + topView.frame.size.height + Notebook.textEditorMargin)
	}
	
	// MARK: - private
	
	private func titleForCurrentChunk() -> String {
		guard let chunk = data?.chunk else { return "unknown" }
		switch chunk.chunkType {
		case .docs:
			if chunk is TextChunk {
				return NSLocalizedString("Markdown", comment: "")
			} else if chunk is Equation {
				return NSLocalizedString("Latex", comment: "")
			}
			return NSLocalizedString("Unknown Document kind", comment: "")
		case .code:
			return NSLocalizedString("R Code", comment: "")
		case .equation:
			guard chunk is Equation else { fatalError() }
			if chunk is InlineChunk {
				return NSLocalizedString("Inline Equation", comment: "")
			} else {
				return NSLocalizedString("Display Equation", comment: "")
			}
		}
	}
	
	private func adjustResults(visible: Bool) {
		if twiddleInProgress {
			resultOuterView.animator().isHidden = !visible
		} else {
			resultOuterView.isHidden = !visible
			resultTwiddle.state = visible ? .on : .off
		}
		adjustSize(animate: false)
	}
	
	// Adjust sizes of each frame (within each item) and adjust the
	// size of data?.height so parent collectionView can layout correctly:
	public func adjustSize(animate: Bool = false) {
		// Prevent recursive laying out during animate:
		guard !layingOut else { return }
		layingOut = true
		defer { layingOut = false }
		
		let startingSize = view.frame.size
		// Set the rects of each frame within each item:
		var topFrame = NSRect.zero, srcFrame = NSRect.zero, resFrame = NSRect.zero, middleFrame = NSRect.zero
		let myWidth = view.frame.size.width	// width of all frames
		
		topFrame = NSRect(x: 0, y: 0, width: myWidth, height: dividerBarHeight)
		middleFrame = middleView != nil ? NSRect(x: 0, y: srcFrame.maxY, width: myWidth, height: dividerBarHeight) : .zero

		// The Top frame height is set by the textContainer of the sourceView. Must ensure the glyphs dimensions have been calculated
		sourceView.layoutManager!.ensureLayout(for: sourceView.textContainer!)
		srcFrame = sourceView.layoutManager!.usedRect(for: sourceView.textContainer!)
		if srcFrame.size.height <= 0 { return }
		srcFrame.size.width = myWidth
		
		// Results frame height is set by the textContainer of the resultView:
		resFrame = dynamicContentFrame
		resFrame.size.width = myWidth
		
		// Add some margin for the txt:
		srcFrame.size.height += verticalMarginHeight
		if resultTextView != nil {
			resFrame.size.height += verticalMarginHeight
		}
		
		// Calculate Y origin of each frame (*from the bottom*!):
		resFrame.origin.y = 0
		let resMaxY = resultOuterView.isHidden ? 0 : resFrame.maxY
		middleFrame.origin.y = resMaxY
		srcFrame.origin.y = middleFrame.maxY
		topFrame.origin.y = srcFrame.maxY
		
		// Set frame size changes. Note: animation (..animator().frame = ..) looks bad here.
		topView.frame = topFrame
		sourceView.enclosingScrollView!.frame = srcFrame
		middleView?.frame = middleFrame
		resultOuterView.frame = resFrame

		// Calculate data?.height:
		var myHeight: CGFloat = topFrame.size.height + srcFrame.size.height
		if middleView != nil {
			myHeight += middleFrame.size.height
		}
		if data!.resultsVisible.value { //} !resultOuterView.isHidden {
			// if results are twiddled open, add it
			myHeight += resFrame.size.height
		}
		let newSize = NSSize(width: myWidth, height: myHeight)
		guard newSize != startingSize else { return }
		view.setFrameSize(newSize)
		data?.height = myHeight
		
		collectionView?.collectionViewLayout?.invalidateLayout()
	}
	
	// MARK: - actions
	/// Asks the delegate to add a chunk after this one
	@IBAction func addChunk(_ sender: Any?) {
		delegate?.addChunk(after: self, sender: sender as? NSButton)
	}
	
	// Hides/Shows results frame if the left most triangle is clicked.
	// (Note: animation is used here with duration = 0  to make default
	// animation not shown.)
	@IBAction func twiddleResults(_ sender: Any?) {
		guard let data = data else { fatalError("how can user twiddle w/o data?") }
		if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
			delegate?.twiddleAllChunks(hide: resultTwiddle.state == .off)
			return
		}
		twiddleInProgress = true
		defer { twiddleInProgress = false }
		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.duration = 0
		data.resultsVisible.value = !data.resultsVisible.value
		NSAnimationContext.endGrouping()
	}
}

extension ChunkViewItem: NSTextViewDelegate {
	func textShouldEndEditing(_ textObject: NSText) -> Bool {
		delegate?.viewItemLostFocus()
		return true
	}

	func textDidChange(_ notification: Notification) {
		guard let textView = notification.object as? SourceTextView else { return }
		data?.source = textView.textStorage!
	}
}

