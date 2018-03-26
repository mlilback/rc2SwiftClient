//
//  FrontMatterView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ReactiveSwift

class FrontMatterViewItem: NSCollectionViewItem, NotebookViewItem {
	// only here because protocol demands, won't be used
	var data: NotebookItemData?
	
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var topView: NSView!

	weak var delegate: NotebookViewItemDelegate?
	var context: EditorContext? { didSet { contextChanged() } }
	private var fontDisposable: Disposable?

	var frontMatterText: String {
		get { return sourceView.string }
		set { sourceView.replace(text: newValue) }
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		topView?.layer?.backgroundColor = noteBookFrontMatterColor.cgColor
		view.layer?.borderColor = NSColor.black.cgColor
		view.layer?.borderWidth = 1
	}
	
	func size(forWidth width: CGFloat) -> NSSize {
		let tmpSize = NSSize(width: width, height: 100)
		sourceView.setFrameSize(tmpSize)
		guard let manager = sourceView.textContainer?.layoutManager, let container = sourceView.textContainer else { return .zero }
		manager.ensureLayout(for: container)
		let textSize = manager.usedRect(for: container).size
		return NSSize(width: width, height: textSize.height + topView.frame.size.height)
	}

	private func contextChanged() {
		fontDisposable?.dispose()
		fontDisposable = context?.editorFont.signal.observeValues { [weak self] font in
			self?.sourceView.font = font
		}
		guard let context = context else { return }
		sourceView.font = context.editorFont.value
	}
	
	@IBAction func addChunk(_ sender: Any?) {
		
	}
}

