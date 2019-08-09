//
//  EquationViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SyntaxParsing
import iosMath

class EquationViewItem: ChunkViewItem {
	@IBOutlet weak var equationView: MTMathUILabel!
	
	override func viewDidLoad() {
		equationView.labelMode = .display
		equationView.contentInsets = MTEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
		equationView.textAlignment = .center
		super.viewDidLoad()
	}
	
	override var nibName: NSNib.Name? { return "EquationViewItem" }
	override var resultView: NSView { return equationView }
	override var resultOuterView: NSView { return equationView }
	
	override func prepareForReuse() {
		super.prepareForReuse()
		equationView.latex = ""
	}
	
	override func dataChanged() {
		super.dataChanged()
		guard let data = data else { return }
		guard data.chunk is Equation else { fatalError("chunk not an equation")}
		equationView.latex = data.source.string
	}
	
	// the equationview draws itself incorrectly when cacheDisplay is called. We draw an image of the equation on top of the normal drag image
	override var draggingImageComponents: [NSDraggingImageComponent] {
		let bitmap = view.bitmapImageRepForCachingDisplay(in: CGRect(origin: .zero, size: view.frame.size))!
		let bitmapData = bitmap.bitmapData
		if bitmapData != nil {
			bzero(bitmapData, bitmap.bytesPerRow * bitmap.pixelsHigh)
		}
		equationView.isHidden = true
		view.cacheDisplay(in: CGRect(origin: .zero, size: bitmap.size), to: bitmap)
		equationView.isHidden = false
		NSGraphicsContext.saveGraphicsState()
		let nscontext = NSGraphicsContext(bitmapImageRep: bitmap)!
		NSGraphicsContext.current = nscontext
		equationView.backgroundColor.setFill()
		let eframe = equationView.frame.insetBy(dx: 1, dy: 1)
		eframe.fill()
		generateEquationImage(size: eframe.size).draw(in: eframe, from: .zero, operation: .sourceOver, fraction: 1.0)
		NSGraphicsContext.restoreGraphicsState()
		let img = NSImage(size: view.frame.size)
		img.addRepresentation(bitmap)

		let orig = super.draggingImageComponents
		orig[0].contents = img
		return orig
	}
	
	/// generates an image of the equation
	func generateEquationImage(size: CGSize) -> NSImage {
		let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
		let nscontext = NSGraphicsContext(bitmapImageRep: rep)!
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = nscontext
		equationView.displayList!.draw(nscontext.cgContext)
		NSGraphicsContext.restoreGraphicsState()
		let image = NSImage(size: size)
		image.addRepresentation(rep)
		return image
	}
}
