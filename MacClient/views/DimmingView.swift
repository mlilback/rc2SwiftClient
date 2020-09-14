//
//  DimmingView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class DimmingView: NSView {
	override required init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
		fatalError("DimmingView does not support NSCoding")
	}

	override func viewDidMoveToSuperview() {
		guard let view = superview else { return }
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer!.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor
		view.addConstraint(leadingAnchor.constraint(equalTo: view.leadingAnchor))
		view.addConstraint(trailingAnchor.constraint(equalTo: view.trailingAnchor))
		view.addConstraint(topAnchor.constraint(equalTo: view.topAnchor))
		view.addConstraint(bottomAnchor.constraint(equalTo: view.bottomAnchor))
		isHidden = true
	}

	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if !isHidden {
			return self
		}
		return super.hitTest(aPoint)
	}
}
