//
//  NotebookEditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import SyntaxParsing
import MJLLogger
import ReactiveSwift

private enum AddChunkType: Int {
	case code = 0
	case mdown
	case equation
}

class NotebookEditorController: AbstractEditorController {
	// MARK: - constants
	let viewItemId = NSUserInterfaceItemIdentifier(rawValue: "NotebookViewItem")
	let equationItemId = NSUserInterfaceItemIdentifier(rawValue: "EquationViewItem")
	let markdownItemId = NSUserInterfaceItemIdentifier(rawValue: "MarkdownViewItem")
	let frontMatterItemId = NSUserInterfaceItemIdentifier(rawValue: "FrontMatterViewItem")
	// The highlighted line where the dropped item will go:
	let dropIndicatorId = NSUserInterfaceItemIdentifier(rawValue: "DropIndicator")
	// Holds dragged item for dropping:
	let notebookItemPasteboardType = NSPasteboard.PasteboardType(rawValue: "io.rc2.client.notebook.entry")
	
	// MARK: - properties
	@IBOutlet weak var notebookView: NSCollectionView!
	@IBOutlet var addChunkPopupMenu: NSMenu!
	
	var rmdDocument: RmdDocument? { return context?.parsedDocument.value }
	var dataArray: [NotebookItemData] = []	// holds data for all items
	var dragIndices: Set<IndexPath>?	// items being dragged
	
	private var sizingItems: [NSUserInterfaceItemIdentifier : NotebookViewItem] = [:]
	private var parsedDocDisposable: Disposable?
	
	// MARK: - standard
	override func viewDidLoad() {
		super.viewDidLoad()
		// Set up CollectionView:
		notebookView.registerForDraggedTypes([notebookItemPasteboardType])
		notebookView.setDraggingSourceOperationMask(.move, forLocal: true)
		notebookView.register(ChunkViewItem.self, forItemWithIdentifier: viewItemId)
		notebookView.register(EquationViewItem.self, forItemWithIdentifier: equationItemId)
		notebookView.register(MarkdownViewItem.self, forItemWithIdentifier: markdownItemId)
		notebookView.register(FrontMatterViewItem.self, forItemWithIdentifier: frontMatterItemId)
		notebookView.register(NotebookDropIndicator.self, forSupplementaryViewOfKind: .interItemGapIndicator, withIdentifier: dropIndicatorId)
		// setup dummy sizing views
		sizingItems[viewItemId] = ChunkViewItem(nibName: nil, bundle: nil)
		sizingItems[equationItemId] = EquationViewItem(nibName: nil, bundle: nil)
		sizingItems[markdownItemId] = MarkdownViewItem(nibName: nil, bundle: nil)
		sizingItems[frontMatterItemId] = FrontMatterViewItem(nibName: nil, bundle: nil)
		// Set some CollectionView layout constrains:
		guard let layout = notebookView.collectionViewLayout as? NSCollectionViewFlowLayout else {
			fatalError() } // make sure we have a layout object
		layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
		layout.minimumLineSpacing = 20.0
		layout.minimumInteritemSpacing = 14.0
	}
	
	// Called initially and when window is resized:
	override func viewWillLayout() {
		// Make sure things are laid out again after all our manual changes:
		notebookView.collectionViewLayout?.invalidateLayout()
		super.viewWillLayout()
	}
	
	// MARK: - editor
	
	override func setContext(context: EditorContext) {
		super.setContext(context: context)
		parsedDocDisposable?.dispose()
		parsedDocDisposable = context.parsedDocument.producer.startWithValues { [weak self] newDocument in
			self?.parsedDocumentChanged(newDocument)
		}
	}
	
	// called when the editor document has changed
	override func loaded(content: String) {
		// we only care about the parsed document, so do nothing here
	}
	
	func parsedDocumentChanged(_ newDocument: RmdDocument?) {
		if let parsed = newDocument {
			dataArray = parsed.chunks.flatMap { return NotebookItemData(chunk: $0, result: "") }
		} else {
			dataArray = []
		}
		notebookView.reloadData()
		notebookView.collectionViewLayout?.invalidateLayout()
	}
	
	override func documentWillSave(_ notification: Notification) {
		// need to convert dataArray back to single source
	}
	
	// MARK: - actions
	
	@IBAction func addChunk(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem, let type = AddChunkType(rawValue: menuItem.tag), let previousChunk = menuItem.representedObject as? ChunkViewItem
			else { Log.warn("addChunk called from non-menu item or with incorrect tag", .app); return }
		switch type {
		case .code:
			rmdDocument?.insertCodeChunk(initalContents: "# R code", at: dataArray.index(of: previousChunk.data!)! + 1)
		case .mdown:
			rmdDocument?.insertTextChunk(initalContents: "# R code", at: dataArray.index(of: previousChunk.data!)! + 1)
		case .equation:
			rmdDocument?.insertEquationChunk(initalContents: "# R code", at: dataArray.index(of: previousChunk.data!)! + 1)
		}
		notebookView.reloadData()
	}
	
	// MARK: - private
	
	func viewItemId(chunk: RmdChunk) -> NSUserInterfaceItemIdentifier {
		switch chunk {
		case is Equation: return equationItemId
		case is TextChunk: return markdownItemId
		default: return viewItemId
		}
	}
}

extension NotebookEditorController: NSMenuDelegate {
	func menuDidClose(_ menu: NSMenu) {
		if menu == addChunkPopupMenu { // clear rep objects which are all set to the NotebookViewItem to add after
			// not supposed to modify menu during this call. perform in a little bit. probably could just do next time through event loop. need action to complete first
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
				self.addChunkPopupMenu.items.forEach { $0.representedObject = nil }
			}
		}
	}
}

// MARK: - NotebookViewItemDelegate
extension NotebookEditorController: NotebookViewItemDelegate {
	func addChunk(after: NotebookViewItem, sender: NSButton?) {
		guard let button = sender else { fatalError("no button supplied for adding chunk") }
		addChunkPopupMenu.items.forEach { $0.representedObject = after }
		addChunkPopupMenu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY), in: button)
	}
	
	func twiddleAllChunks(hide: Bool) {
		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.duration = 0
		dataArray.forEach { $0.resultsVisible.value = !hide }
		NSAnimationContext.endGrouping()
	}
}

// MARK: - NSCollectionViewDataSource
extension NotebookEditorController: NSCollectionViewDataSource {
//	func numberOfSections(in collectionView: NSCollectionView) -> Int {
//		return 2
//	}
	
	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
//		if section == 0 { return 1}
		return dataArray.count + 1
	}
	
	// Inits views for each item given its indexPath:
	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem
	{
		if indexPath.item == 0 {
//		guard indexPath.section == 1 else {
			guard let fmItem = collectionView.makeItem(withIdentifier: frontMatterItemId, for: indexPath) as? FrontMatterViewItem else { fatalError() }
			fmItem.context = context
			fmItem.delegate = self
			fmItem.rmdDocument = rmdDocument
			return fmItem
		}
		let itemData = dataArray[indexPath.item - 1]
		let itemId = viewItemId(chunk: itemData.chunk)
		let itemView: NSCollectionViewItem
		guard let view = collectionView.makeItem(withIdentifier: itemId, for: indexPath) as? NotebookViewItem else { fatalError() }
		itemView = view as! NSCollectionViewItem
		view.context = context
		view.data = itemData
		view.delegate = self
		return itemView
	}
	
	// Inits the horizontal line used to highlight where the drop will go:
	func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView
	{
		if kind == .interItemGapIndicator {
			return collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: dropIndicatorId, for: indexPath)
		}
		// All other supplementary views go here (like footers), which are currently none:
		return collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier(rawValue: ""), for: indexPath)
	}
}

// MARK: - NSCollectionViewDelegate

extension NotebookEditorController: NSCollectionViewDelegateFlowLayout {
	
	// Returns the size of each item:
	func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize
	{
		// if context not set, return fake size, will be caused again
		guard let context = context, collectionView.collectionViewLayout is NSCollectionViewFlowLayout else {
			return NSSize(width: 100, height: 120)
		}
		if indexPath.item == 0 {
			let fitem = sizingItems[frontMatterItemId] as! FrontMatterViewItem
			_ = fitem.view
			fitem.context = context
			fitem.rmdDocument = rmdDocument
			return fitem.size(forWidth: collectionView.visibleWidth)
		}
		let dataItem = dataArray[indexPath.item - 1]
		guard let dummyItem = sizingItems[viewItemId(chunk: dataItem.chunk)] as? ChunkViewItem else {
			let mitem = sizingItems[markdownItemId] as! MarkdownViewItem
			_ = mitem.view
			mitem.data = dataItem
			mitem.context = context
			let sz = mitem.size(forWidth: collectionView.visibleWidth)
			return sz
		}
		dummyItem.prepareForReuse()
		dummyItem.data = dataItem
		dummyItem.context = context
		dummyItem.adjustSize()
		let sz = NSSize(width: collectionView.visibleWidth, height: dummyItem.view.frame.size.height)
		return sz
	}
	
	// Places the data for the drag operation on the pasteboard:
	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		let includesFrontMatter = indexPaths.contains(where: { $0.item == 0 })
		return !includesFrontMatter
	}
	
	// Provides the pasteboard writer for the item at the specified index:
	func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt index: Int) -> NSPasteboardWriting? {
		let pbitem = NSPasteboardItem()
		pbitem.setString("\(index)", forType: notebookItemPasteboardType)
		return pbitem
	}
	
	// Notifies your delegate that a drag session is about to begin:
	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
		dragIndices = indexPaths // get the dragIndices
	}
	
	// Notifies your delegate that a drag session ended:
	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
		dragIndices = nil		// reset dragIndices
	}
	
	// Returns what type of drag operation is allowed:
	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		guard let _ = dragIndices else { return [] } // make sure we have indices being dragged
		// if moving to top, change location to after front-matter
		if proposedDropIndexPath.pointee.item < 1 { proposedDropIndexPath.pointee = NSIndexPath(forItem: 1, inSection: 0) }
		// Turn any drop on an item to a drop before since none are containers:
		if proposedDropOperation.pointee == .on {
			proposedDropOperation.pointee = .before }
		return .move
	}
	
	// Performs the drag (move) opperation, both updating our data and animating the move:
	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		guard let fromIndexPath = dragIndices?.first else {
			return false
		}
		let fromIndex = fromIndexPath.item - 1
		var toIndex = indexPath.item - 1
		if toIndex > fromIndex { toIndex -= 1 }
		Log.debug("moving \(fromIndex) to \(toIndex)", .app)
		let itemData = dataArray[fromIndex]
		dataArray.remove(at: fromIndex)	// must be done first
		dataArray.insert(itemData, at: toIndex)
		collectionView.animator().moveItem(at: IndexPath(item: fromIndex+1, section: 0), to: IndexPath(item: toIndex+1, section: 0))
		return true
	}
}

// MARK: -

// Uses width of parent view to determine item width minus insets
extension NSCollectionView {
	/// the width of the collectionview minus the insets
	var visibleWidth: CGFloat {
		guard let layout = collectionViewLayout as? NSCollectionViewFlowLayout else {
			return frame.width }
		return frame.width - layout.sectionInset.left - layout.sectionInset.right
	}
}


// MARK: -
class NoScrollView: NSScrollView {
	override func scrollWheel(with event: NSEvent) {
		nextResponder?.scrollWheel(with: event)
	}
}

