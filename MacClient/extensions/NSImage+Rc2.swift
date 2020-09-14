//
//  NSImage+Rc2.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//
// from https://gist.github.com/MaciejGad/11d8469b218817290ee77012edb46608

import Cocoa

extension NSImage {

	/// Returns the height of the current image.
	var height: CGFloat {
		return self.size.height
	}

	/// Returns the width of the current image.
	var width: CGFloat {
		return self.size.width
	}

	/// Returns a png representation of the current image.
	var pngRepresentation: Data? {
		if let tiff = self.tiffRepresentation, let tiffData = NSBitmapImageRep(data: tiff) {
			return tiffData.representation(using: .png, properties: [:])
		}

		return nil
	}

	/// Draws smallImage on the bottom right corner of largeImage at half size
	///
	/// - Parameters:
	///   - image: the image to overlay in the bottom right
	///   - scale: the scale to draw image at. Defaults to .5
	func overlay(image: NSImage, scale: CGFloat = 0.5) {
		assert(scale > 0 && scale < 1.0, "invalid scale for overlay image")
		self.lockFocus()
		NSGraphicsContext.current?.imageInterpolation = .high
		let miniWidth = self.size.width * scale
		image.draw(in: CGRect(x: miniWidth, y: 0, width: miniWidth, height: miniWidth), from: .zero, operation: .sourceOver, fraction: 1.0)
		self.unlockFocus()
	}

	///  Copies the current image and resizes it to the given size.
	///
	///  - parameter size: The size of the new image.
	///
	///  - returns: The resized copy of the given image.
	func copy(size: NSSize) -> NSImage? {
		// Create a new rect with given width and height
		let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

		// Get the best representation for the given size.
		guard let rep = self.bestRepresentation(for: frame, context: nil, hints: nil) else {
			return nil
		}

		// Create an empty image with the given size.
		let img = NSImage(size: size)

		// Set the drawing context and make sure to remove the focus before returning.
		img.lockFocus()
		defer { img.unlockFocus() }

		// Draw the new image
		if rep.draw(in: frame) {
			return img
		}

		// Return nil in case something went wrong.
		return nil
	}

	///  Copies the current image and resizes it to the size of the given NSSize, while
	///  maintaining the aspect ratio of the original image.
	///
	///  - parameter size: The size of the new image.
	///
	///  - returns: The resized copy of the given image.
	func resizeWhileMaintainingAspectRatioToSize(size: NSSize) -> NSImage? {
		let newSize: NSSize

		let widthRatio = size.width / self.width
		let heightRatio = size.height / self.height

		if widthRatio > heightRatio {
			newSize = NSSize(width: floor(self.width * widthRatio), height: floor(self.height * widthRatio))
		} else {
			newSize = NSSize(width: floor(self.width * heightRatio), height: floor(self.height * heightRatio))
		}

		return self.copy(size: newSize)
	}

	///  Copies and crops an image to the supplied size.
	///
	///  - parameter size: The size of the new image.
	///
	///  - returns: The cropped copy of the given image.
	func crop(size: NSSize) -> NSImage? {
		// Resize the current image, while preserving the aspect ratio.
		guard let resized = self.resizeWhileMaintainingAspectRatioToSize(size: size) else {
			return nil
		}
		// Get some points to center the cropping area.
		let x = floor((resized.width - size.width) / 2)
		let y = floor((resized.height - size.height) / 2)

		// Create the cropping frame.
		let frame = NSRect(x: x, y: y, width: size.width, height: size.height)

		// Get the best representation of the image for the given cropping frame.
		guard let rep = resized.bestRepresentation(for: frame, context: nil, hints: nil) else {
			return nil
		}

		// Create a new image with the new size
		let img = NSImage(size: size)

		img.lockFocus()
		defer { img.unlockFocus() }

		if rep.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height),
					from: frame,
					operation: NSCompositingOperation.copy,
					fraction: 1.0,
					respectFlipped: false,
					hints: [:]) {
			// Return the cropped image.
			return img
		}

		// Return nil in case anything fails.
		return nil
	}

	///  Saves the PNG representation of the current image to the HD.
	///
	/// - parameter url: The location url to which to write the png file.
	func savePNGRepresentationToURL(url: URL) throws {
		if let png = self.pngRepresentation {
			try png.write(to: url, options: .atomicWrite)
		}
	}
}
