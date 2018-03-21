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
import MJLLogger

protocol NotebookViewItemDelegate: class {
	func addChunk(after: NotebookViewItem, sender: NSButton?)
}

class NotebookViewItem: NSCollectionViewItem {
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var resultTextView: SourceTextView?
	@IBOutlet weak var topView: NSView!
	@IBOutlet weak var middleView: NSView!
	@IBOutlet weak var resultTwiddle: NSButton!
	@IBOutlet weak var chunkTypeLabel: NSTextField!
	@IBOutlet weak var addChunkButton: NSButton!
	var layingOut = false
	
	/// if a subclass uses a non-NSTextView results view, this needs to be overridden to calculate frame
	var resultView: NSView { return resultTextView! }
	/// if the result view shown is in a scrollview, this is the scrollview. otherwise it is the result view.
	var resultOuterView: NSView { return resultView.enclosingScrollView ?? resultView }
	/// if results are text, figure out the frame needed to show the content. otherwise, using fixed size
	var dynamicContentFrame: CGRect { return resultTextView?.layoutManager!.usedRect(for: resultTextView!.textContainer!) ?? resultView.frame }
	
	weak var delegate: NotebookViewItemDelegate?
	var data: NotebookItemData? { didSet { dataChanged() } }
	var context: EditorContext? { didSet { contextChanged() } }
	private var fontDisposable: Disposable?

	deinit {
		fontDisposable?.dispose()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Get notified if view's bounds change:
		NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: sourceView)
		NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: resultView)
		
		// Set background colors for top and middle views:
		topView.wantsLayer = true
		topView.layer?.backgroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0).cgColor
		middleView.wantsLayer = true
		middleView.layer?.backgroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0).cgColor
		// Note: results content background is set its .xib.
		sourceView.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
		//  Create a callback to adjustSize, so NotebookEntryView can call it during its layout:
		guard let myview = view as? NotebookEntryView else { fatalError() }
		myview.performLayout = { [weak self] in
			self?.adjustSize() }
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		// Hack that fixes a bug where usedRect for initial text is off by two pixels.
		// As soon as the user changes the rect, it is correct.
		data!.source.append(NSAttributedString(string: " "))
		data!.source.deleteCharacters(in: NSRange(location: data!.source.length - 1, length: 1))
	}
	
	// Recycle an unseen NotebookViewItem container for different visible data:
	override func prepareForReuse() {
		super.prepareForReuse()
		data = nil
		sourceView.replace(text: "")
		resultTextView?.replace(text: "")
	}

	// If the view size changes, re-adjust data height:
	@objc func boundsChanged(_ note: Notification) {
		adjustSize()
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
	
	private func dataChanged() {
		guard let context = context else { fatalError("context must be set before data") }
		// Callbacks from changes in NSTextViews that adjust the item view size:
		sourceView.changeCallback = { [weak self] in
			self?.adjustSize()
		}
		resultTextView?.changeCallback = { [weak self] in
			self?.adjustSize()
			Log.debug("resultView.changeCallback", .app)
		}
		data?.source.font = context.editorFont.value
		// Sets each view's string from the data's string
		guard let sourceStorage = sourceView?.textStorage else { fatalError() }
		if let attrStr = data?.chunk.attributedContents {
			sourceStorage.replaceCharacters(in: sourceStorage.string.fullNSRange, with: attrStr)
		} else {
			sourceView.replace(text: data?.source.string ?? "")
		}
		resultTextView?.replace(text: data?.result.string ?? "")
		//adjust label
		chunkTypeLabel.stringValue = titleForCurrentChunk()
	}

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
	
	// Adjust sizes of each frame (within each item) and adjust the
	// size of data?.height so parent collectionView can layout correctly:
	public func adjustSize(animate: Bool = false) {
		// Prevent recursive laying out during animate:
		guard !layingOut else { return }
		layingOut = true
		defer { layingOut = false }
		
		// Set the rects of each frame within each item:
		var topFrame = NSRect.zero, srcFrame = NSRect.zero, resFrame = NSRect.zero, middleFrame = NSRect.zero
		let myWidth = view.frame.size.width	// width of all frames
		
		topFrame = NSRect(x: 0, y: 0, width: myWidth, height: 21)
		middleFrame = NSRect(x: 0, y: srcFrame.maxY, width: myWidth, height: 21)

		// The Top frame height is set by the textContainer of the sourceView:
		srcFrame = sourceView.layoutManager!.usedRect(for: sourceView.textContainer!)
		srcFrame.size.width = myWidth
		
		// Results frame height is set by the textContainer of the resultView:
		resFrame = dynamicContentFrame
		resFrame.size.width = myWidth
		
		// Add some margin for the txt:
		srcFrame.size.height += 10; resFrame.size.height += 10
		
		// Calculate Y origin of each frame (*from the bottom*!):
		resFrame.origin.y = 0
		let resMaxY = resultOuterView.isHidden ? 0 : resFrame.maxY
		middleFrame.origin.y = resMaxY
		srcFrame.origin.y = middleFrame.maxY
		topFrame.origin.y = srcFrame.maxY
		
		// Set frame size changes. Note: animation (..animator().frame = ..) looks bad here.
		topView.frame = topFrame
		sourceView.enclosingScrollView!.frame = srcFrame
		middleView.frame = middleFrame
		resultOuterView.frame = resFrame

		// Calculate data?.height:
		var myHeight: CGFloat = topFrame.size.height + srcFrame.size.height + middleFrame.size.height
		if !resultOuterView.isHidden {
			// if results are twiddled open, add it
			myHeight += resFrame.size.height
		}
		view.setFrameSize(NSSize(width: myWidth, height: myHeight))
		data?.height = myHeight
		
		// Tell parent view to re-layout:
		collectionView?.collectionViewLayout?.invalidateLayout()
	}
	
	/// Asks the delegate to add a chunk after this one
	@IBAction func addChunk(_ sender: Any?) {
		delegate?.addChunk(after: self, sender: sender as? NSButton)
	}
	
	// Hides/Shows results frame if the left most triangle is clicked.
	// (Note: animation is used here with duration = 0  to make default
	// animation not shown.)
	@IBAction func twiddleResults(_ sender: Any?) {
		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.duration = 0
		resultOuterView.animator().isHidden = resultTwiddle.state == .off
		adjustSize(animate: false)
		NSAnimationContext.endGrouping()
	}
}

