//
//  ChunkHeaderView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc class ChunkHeaderView: NSView {
	static let defaultHeight = CGFloat(20)
	var chunk: DocumentChunk?
	var box: NSBox!
	var topConstraint: NSLayoutConstraint?
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		box = NSBox(frame: frame.insetBy(dx: 2, dy: 2))
		box.boxType = .custom
		box.fillColor = NSColor.systemPink.withAlphaComponent(0.2)
		box.borderType = .noBorder
//		layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.3).cgColor
		box.translatesAutoresizingMaskIntoConstraints = false
		addSubview(box)
		box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -2).isActive = true
		box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2).isActive = true
		box.topAnchor.constraint(equalTo: topAnchor, constant: -2).isActive = true
		box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2).isActive = true
	}
	
	required init?(coder: NSCoder) {
		fatalError("arching not supported")
	}
}
