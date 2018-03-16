//
//  NotebookCollectionLayout.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger

// Determined the actual size and position of the DropIndicator (newRect):
class NotebookCollectionLayout: NSCollectionViewFlowLayout {
	
	override func layoutAttributesForDropTarget(at pointInCollectionView: NSPoint) -> NSCollectionViewLayoutAttributes? {
		let superAttrs = super.layoutAttributesForDropTarget(at: pointInCollectionView)
		// Check if we have the following to calc newRect, else return superAttrs unchanged:
		guard let cView = collectionView else {
			Log.error("No collectionView!", .app); fatalError() }
		guard superAttrs != nil else {
			Log.warn("No superAttrs!", .app); return nil }
		// Very common - so no fatalError here:
		guard superAttrs?.frame != NSRect.zero else {
			return superAttrs
		}
		
		let attrs = superAttrs!.copy() as! NSCollectionViewLayoutAttributes
		// Calc vars for newRect:
		let itemWidth = cView.frame.width - sectionInset.left - sectionInset.right
		let height = min(attrs.frame.height, attrs.frame.width)
		var yOff = -height
		let y = attrs.frame.origin.y
		
		// Handle end-case differently:
		guard let indexPath = attrs.indexPath else {
			Log.warn("No defAttrs.indexPath!", .app); return attrs
		}
		let numOfItems = cView.dataSource?.collectionView(cView, numberOfItemsInSection: indexPath.section) ?? 0
		if  indexPath.item >= numOfItems {
			yOff = attrs.frame.height
		}
		
		// Make newRect and set superAttrs!.frame to it:
		let newRect = CGRect(x: sectionInset.left, y: y + yOff, width: itemWidth, height: height)
		attrs.frame = newRect
		Log.info("returning attrs \(attrs.frame)", .app)
		return attrs
	}
}
