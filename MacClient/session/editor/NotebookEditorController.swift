//
//  NotebookEditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking
import SyntaxParsing

class NotebookEditorController: AbstractEditorController {
	// MARK: - constants
	let viewItemId = NSUserInterfaceItemIdentifier(rawValue: "NotebookViewItem")
	// The highlighted line where the dropped item will go:
	let dropIndicatorId = NSUserInterfaceItemIdentifier(rawValue: "DropIndicator")
	// Holds dragged item for dropping:
	let notebookItemPasteboardType = NSPasteboard.PasteboardType(rawValue: "io.rc2.client.notebook.entry")

	// MARK: - properties
	@IBOutlet weak var notebookView: NSCollectionView!

	var dataArray: [NotebookItemData] = []	// holds data for all items
	var dragIndices: Set<IndexPath>?	// items being dragged

	private var parser: SyntaxParser?
	private let storage = NSTextStorage()

	// MARK: - Standard
	override func viewDidLoad() {
		super.viewDidLoad()
		// Set up CollectionView:
		notebookView.registerForDraggedTypes([notebookItemPasteboardType])
		notebookView.setDraggingSourceOperationMask(.move, forLocal: true)
		notebookView.register(NotebookViewItem.self, forItemWithIdentifier: viewItemId)
		notebookView.register(NotebookDropIndicator.self, forSupplementaryViewOfKind: .interItemGapIndicator, withIdentifier: dropIndicatorId)
		// Set some CollectionView layout constrains:
		guard let layout = notebookView.collectionViewLayout as? NSCollectionViewFlowLayout else {
			fatalError() } // make sure we have a layout object
		layout.sectionInset = NSEdgeInsets(top: 20, left: 8, bottom: 20, right: 8)
		layout.minimumLineSpacing = 20.0
		layout.minimumInteritemSpacing = 14.0
	}

	// Called initially and when window is resized:
	override func viewWillLayout() {
		// Make sure things are laid out again after all our manual changes:
		notebookView.collectionViewLayout?.invalidateLayout()
		super.viewWillLayout()
	}

	override func loaded(document: EditorDocument, content: String) {
		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: document.file.fileType) { (topic) in
			return HelpController.shared.hasTopic(topic)
		}
		storage.replaceCharacters(in: storage.string.fullNSRange, with: content)
		_ = parser?.parse()
		dataArray = parser!.chunks.map { NotebookItemData(chunk: $0, source: content, result: "") }
		notebookView.reloadData()
		notebookView.collectionViewLayout?.invalidateLayout()
	}

	// MARK: - CodeEditor
	var documentLoaded: Bool { return false }
	
	override func setContext(context: EditorContext) {
		super.setContext(context: context)
	}

	func save(state: inout SessionState.EditorState) {
		
	}
	
	func restore(state: SessionState.EditorState) {
		
	}
	
	func fileChanged(file: AppFile?) {
		
	}
}

// MARK: - NSCollectionViewDataSource
extension NotebookEditorController: NSCollectionViewDataSource {
	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return dataArray.count
	}
	
	// Inits views for each item given its indexPath:
	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem
	{
		let itemData = dataArray[indexPath.item]
		guard let view = collectionView.makeItem(withIdentifier: viewItemId, for: indexPath) as? NotebookViewItem else { fatalError() }
		view.context = context
		view.data = itemData
		return view
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
		let dataItem = dataArray[indexPath.item]
		let sz = NSSize(width: collectionView.visibleWidth, height: dataItem.height)
		//		let str = dataItem.source.string[dataItem.source.string.startIndex]
		//		print("sz for \(indexPath.item) is \(sz)")
		return sz
	}
	
	// Places the data for the drag operation on the pasteboard:
	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return true // when front matter is displayed, will need to return false for it
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
		// Turn any drop on an item to a drop before since none are containers:
		if proposedDropOperation.pointee == .on {
			proposedDropOperation.pointee = .before }
		return .move
	}
	
	// Performs the drag (move) opperation, both updating our data and animating the move:
	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		for fromIndexPath in dragIndices! {
			let fromIndex = fromIndexPath.item
			var toIndex = indexPath.item
			if toIndex > fromIndex { toIndex -= 1 }
			print("moving \(fromIndex) to \(toIndex)")
			let itemData = dataArray[fromIndex]
			dataArray.remove(at: fromIndex)	// must be done first
			dataArray.insert(itemData, at: toIndex)
			collectionView.animator().moveItem(at: fromIndexPath, to: IndexPath(item: toIndex, section: 0))
		}
		return true
	}
}

// MARK: -

// Uses width of parent view to determine item width minus insets
extension NSCollectionView {
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
