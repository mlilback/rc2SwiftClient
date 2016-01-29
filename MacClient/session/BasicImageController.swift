//
//  BasicImageController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class DisplayableImage {
	let imageId:Int
	let name:String
	let image:NSImage
	
	init(imageId:Int, name:String, image:NSImage) {
		self.imageId = imageId
		self.name = name
		self.image = image
	}

	convenience init(_ simage:SessionImage, image:NSImage) {
		self.init(imageId: simage.id, name:simage.name, image:image)
	}
}

class BasicImageController: NSViewController {
	@IBOutlet var imageView: NSImageView?
	@IBOutlet var labelField: NSTextField?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var nagivateButton: NSSegmentedControl?
	
	var images: [DisplayableImage] = []
	var currentIndex:Int = 0 { didSet {
			if currentIndex < 0 {
				currentIndex = 0
			} else if currentIndex >= images.count {
				currentIndex = max(images.count - 1, 0)
			}
			switchImage()
		}
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		switchImage()
	}
	
	@IBAction func shareClicked(sender:AnyObject?) {
		
	}
	
	@IBAction func navigateClicked(sender:AnyObject?) {
		
	}
	
	private func switchImage() {
		imageView?.animator().image = images[currentIndex].image
		labelField?.stringValue = images[currentIndex].name
	}
}
