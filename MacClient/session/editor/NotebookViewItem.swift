//
//  NotebookViewItem.swift
//  Rc2Notebook
//
//  Created by Mark Lilback on 1/31/18.
//  Copyright © 2018 Mark Lilback. All rights reserved.
//

import Cocoa

class NotebookViewItem: NSCollectionViewItem {
	let fontSize = CGFloat(13)
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var resultView: SourceTextView!
	@IBOutlet weak var topView: NSView!
	@IBOutlet weak var middleView: NSView!
	@IBOutlet weak var resultTwiddle: NSButton!
	var layingOut = false
	
	var data: NotebookItemData? {
		didSet {
			// Set font of can new data so it's the same:
			guard let font = NSFont.userFixedPitchFont(ofSize: fontSize) else { fatalError() }
			data?.source.font = font
			sourceView.font = font
			// Callbacks from changes in NSTextViews that adjust the item view size:
			sourceView.changeCallback = { [weak self] in
				self?.adjustSize()
			}
			resultView.changeCallback = { [weak self] in
				self?.adjustSize()
//				print("resultView.changeCallback")
			}
			// Sets each view's string from the data's string:
			sourceView.replace(text: data?.source.string ?? "")
			resultView.replace(text: data?.result.string ?? "")
		}
	}

	// Setup:
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Get notified if view's bounds change:
		NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: sourceView)
		NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: resultView)
		
		// Initial font:
		if let font = NSFont.userFixedPitchFont(ofSize: fontSize) {
			sourceView.font = font
		}
		// Set background colors for top and middle views:
		topView.wantsLayer = true
		topView.layer?.backgroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0).cgColor
		middleView.wantsLayer = true
		middleView.layer?.backgroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0).cgColor
		// Note: results content background is set its .xib.

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
		resultView.replace(text: "")
	}

	// If the view size changes, re-adjust data height:
	@objc func boundsChanged(_ note: Notification) {
		adjustSize()
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
		resFrame = resultView.layoutManager!.usedRect(for: resultView.textContainer!)
		resFrame.size.width = myWidth
		
		// Add some margin for the txt:
		srcFrame.size.height += 10; resFrame.size.height += 10
		
		// Calculate Y origin of each frame (*from the bottom*!):
		resFrame.origin.y = 0
		let resMaxY = resultView.enclosingScrollView!.isHidden ? 0 : resFrame.maxY
		middleFrame.origin.y = resMaxY
		srcFrame.origin.y = middleFrame.maxY
		topFrame.origin.y = srcFrame.maxY
		
		// Set frame size changes. Note: animation (..animator().frame = ..) looks bad here.
		topView.frame = topFrame
		sourceView.enclosingScrollView!.frame = srcFrame
		middleView.frame = middleFrame
		resultView.enclosingScrollView!.frame = resFrame

		// Calculate data?.height:
		var myHeight: CGFloat = topFrame.size.height + srcFrame.size.height + middleFrame.size.height
		if !resultView.enclosingScrollView!.isHidden {
			// if results are twiddled open, add it
			myHeight += resFrame.size.height
		}
		view.setFrameSize(NSSize(width: myWidth, height: myHeight))
		data?.height = myHeight
		
		// Tell parent view to re-layout:
		collectionView?.collectionViewLayout?.invalidateLayout()
	}

	// Hides/Shows results frame if the left most triangle is clicked.
	// (Note: animation is used here with duration = 0  to make default
	// animation not shown.)
	@IBAction func twiddleResults(_ sender: Any?) {
		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.duration = 0
		resultView.enclosingScrollView?.animator().isHidden = resultTwiddle.state == .off
		adjustSize(animate: false)
		NSAnimationContext.endGrouping()
	}
}

