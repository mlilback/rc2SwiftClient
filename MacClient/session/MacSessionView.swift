//
//  MacSessionView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let animationKey = "SessionAnimation"
let defaultSplitPercent: CGFloat = 0.5

class MacSessionView: NSView {
	@IBOutlet var leftXConstraint: NSLayoutConstraint?
	@IBOutlet var editorWidthConstraint: NSLayoutConstraint?
	@IBOutlet var splitterView: MacSplitter?
	@IBOutlet var leftView: NSView?
	@IBOutlet var editorView: NSView?
	@IBOutlet var outputView: NSView?
	var leftViewAnimating: Bool = false
	var editorWidthLocked: Bool = false
	var draggingSplitter: Bool = false
	var splitterPercent: CGFloat = defaultSplitPercent
	var dragTrackingArea: NSTrackingArea?
	
	var leftViewVisible : Bool {
		get { return NSMinX((leftView?.frame)!) >= 0 }
		set { toggleLeftView(self) }
	}
	var editorWidth: CGFloat {
		get { return (editorWidthConstraint?.constant)! }
		set { if newValue > 100 { editorWidthConstraint?.animator().constant = newValue } }
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		editorWidthConstraint?.priority = NSLayoutPriorityDragThatCannotResizeWindow
		editorWidthConstraint?.constant = 400
	}
	
	@IBAction func toggleEditorWidthLock(sender:AnyObject?) {
		editorWidthLocked = !editorWidthLocked
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		if menuItem.action == "toggleEditorWidthLock:" {
			menuItem.state = editorWidthLocked ? NSOnState : NSOffState
			return true
		}
		return super.validateMenuItem(menuItem)
	}
	
	func adjustViewSizes() {
		let newWidth: CGFloat = (splitterView?.frame.origin.x)! - NSMinX((editorView?.frame)!) + 1
		editorWidthConstraint?.animator().constant = newWidth
		needsUpdateConstraints = true
	}
	
	func computeEditorWidth() -> CGFloat {
		let leftWidth: CGFloat = (leftView?.frame.size.width)!
		let newWidth: CGFloat = (leftView?.frame.origin.x)! + leftWidth
		let splittableWidth = frame.size.width - newWidth - (splitterView?.frame.size.width)!
		let editWidth = splittableWidth * splitterPercent
		return editWidth
	}
	
	override func resizeSubviewsWithOldSize(oldSize: NSSize) {
		super.resizeSubviewsWithOldSize(oldSize)
		if editorWidthLocked || draggingSplitter || leftViewAnimating {
			return
		}
		let editWidth = computeEditorWidth()
		if ((window?.inLiveResize) != nil) {
			let delta = frame.size.width - oldSize.width
			let newWidth = (editorView?.frame.size.width)! + (delta / 2)
			//don't want animation
			editorWidthConstraint?.constant = newWidth
		} else {
			editorWidthConstraint?.animator().constant = editWidth
		}
	}
	
	func toggleLeftView(sender:AnyObject?) {
		let leftWidth: CGFloat = (leftView?.frame.size.width)!
		let newX = NSMinX((leftView?.frame)!) >= 0 ? -leftWidth : 0
		let splitWidth: CGFloat = (splitterView?.frame.size.width)!
		var newWidth: CGFloat = 0
		if newX < 0 {
			newWidth = (frame.size.width - splitWidth) / 2
		} else {
			newWidth = (frame.size.width - splitWidth - leftWidth) / 2
		}
		leftViewAnimating = true
		NSAnimationContext.runAnimationGroup({ (context) -> Void in
			context.duration = 0.3
			if !self.editorWidthLocked {
				self.editorWidthConstraint?.animator().constant = newWidth
			}
			self.leftXConstraint?.animator().constant = newX
		}) { () -> Void in
			self.leftViewAnimating = false
		}
	}
	
	//MARK: - Dragging
	
	override func mouseDown(theEvent: NSEvent) {
		let loc = convertPoint(theEvent.locationInWindow, fromView: nil)
		let frame = NSInsetRect((splitterView?.frame)!, -2, 0)
		if NSPointInRect(loc, frame) {
			draggingSplitter = true
			dragTrackingArea = NSTrackingArea(rect: bounds, options: [.CursorUpdate, .InVisibleRect, .ActiveInKeyWindow], owner: self, userInfo: nil)
			addTrackingArea(dragTrackingArea!)
		}
	}
	
	override func mouseDragged(theEvent: NSEvent) {
		guard draggingSplitter else { return }
		let loc = convertPoint(theEvent.locationInWindow, fromView: nil)
		let newWidth = loc.x - NSMinX((editorView?.frame)!)
		if newWidth >= 200 {
			editorWidthConstraint?.constant = newWidth
		}
	}
	
	override func mouseUp(theEvent: NSEvent) {
		guard draggingSplitter else { return }
		draggingSplitter = false
		removeTrackingArea(dragTrackingArea!)
		dragTrackingArea = nil
		let editWidth = editorWidthConstraint?.constant //editorView?.frame.size.width
		splitterPercent = editWidth! / (editWidth! + (outputView?.frame.size.width)!)
	}
	
	override func cursorUpdate(theEvent: NSEvent) {
		if dragTrackingArea != nil {
			NSCursor.resizeLeftRightCursor().set()
		}
	}
}
