//
//  ImageOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CoreServices
import os

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}


class DisplayableImage: NSObject {
	let imageId:Int
	let name:String
	var image:NSImage?
	
	init(imageId:Int, name:String) {
		self.imageId = imageId
		self.name = name
	}
	
	convenience init(_ simage:SessionImage) {
		self.init(imageId: simage.id, name:simage.name)
	}
}

class ImageOutputController: NSViewController, NSPageControllerDelegate, NSSharingServicePickerDelegate {
	@IBOutlet var containerView: NSView?
	@IBOutlet var labelField: NSTextField?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var navigateButton: NSSegmentedControl?

	var pageController: NSPageController?
	var batchImages: [DisplayableImage] = []
	var firstIndex: Int = 0
	var imageCache: ImageCache?
	var myShareServices: [NSSharingService] = []
	
	override func viewDidLoad() {
		super.viewDidLoad()
		pageController = NSPageController()
		pageController?.delegate = self
		pageController?.transitionStyle = .stackBook
		pageController?.view = containerView!
		view.wantsLayer = true
		shareButton?.sendAction(on: NSEventMask(rawValue: UInt64(Int(NSEventMask.leftMouseDown.rawValue))))
		view.layer?.backgroundColor = PlatformColor.white.cgColor
		labelField?.stringValue = ""
		navigateButton?.setEnabled(false, forSegment: 0)
		navigateButton?.setEnabled(false, forSegment: 1)
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		if batchImages.count > 0 && pageController?.arrangedObjects.count < 1 {
			pageController?.arrangedObjects = batchImages
			pageController?.selectedIndex = firstIndex
			labelField?.stringValue = batchImages[firstIndex].name
		}
	}
	
	func displayImageAtIndex(_ index:Int, images:[SessionImage]) {
		batchImages = images.map { (simg) -> DisplayableImage in
			return DisplayableImage(imageId: simg.id, name: simg.name)
		}
		firstIndex = index
		pageController?.arrangedObjects = batchImages
		pageController?.selectedIndex = index
		navigateButton?.setEnabled(index > 0, forSegment: 0)
		navigateButton?.setEnabled(index + 1 < images.count, forSegment: 1)
	}
	
	@IBAction func navigateClicked(_ sender:AnyObject?) {
		switch ((navigateButton?.selectedSegment)!) {
		case 0:
			pageController?.navigateBack(self)
		case 1:
			pageController?.navigateForward(self)
		default:
			break
		}
	}
	
	@IBAction func shareImage(_ sender:AnyObject?) {
		let dimg = batchImages[(pageController?.selectedIndex)!]
		let imgUrl = imageCache?.urlForCachedImage(dimg.imageId)
		myShareServices.removeAll()
		let wspace = NSWorkspace()
		if let appUrl = wspace.urlForApplication(toOpen: imgUrl!) {
			let appIcon = wspace.icon(forFile: appUrl.path)
			let appName = appUrl.localizedName()
			myShareServices.append(NSSharingService(title: "Open in \(appName)", image: appIcon, alternateImage: nil, handler: {
					var urlToUse = imgUrl!
					do {
						try urlToUse = Rc2DefaultFileManager().copyURLToTemporaryLocation(imgUrl!)
					} catch let err as NSError {
						os_log("error copying to tmp: %@", type:.error, err)
					}
					wspace.openFile(urlToUse.path, withApplication: appUrl.path)
				}))
		}
		let picker = NSSharingServicePicker(items: [dimg.image!])
		picker.delegate = self
		picker.show(relativeTo: (shareButton?.bounds)!, of: shareButton!, preferredEdge: .maxY)
	}
	
	func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService]
	{
		return myShareServices + proposedServices
	}
	
	func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
		if let dimage = object as? DisplayableImage {
			labelField?.stringValue = dimage.name
			let index = batchImages.index(of: dimage)!
			navigateButton?.setEnabled(index > 0, forSegment: 0)
			navigateButton?.setEnabled(index < batchImages.count-1, forSegment: 1)
		}
	}
	
	func pageController(_ pageController: NSPageController, identifierFor object: Any) -> String {
		return "\(batchImages.index(of: object as! DisplayableImage)!)"
	}
	
	func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: String) -> NSViewController
	{
		let vc = ImageViewController()
		let iv = NSImageView(frame: (containerView?.frame)!)
		iv.imageFrameStyle = .none
		iv.translatesAutoresizingMaskIntoConstraints = false
		iv.setContentHuggingPriority(200, for: .horizontal)
		iv.setContentCompressionResistancePriority(200, for: .horizontal)
		iv.imageScaling = .scaleProportionallyDown
		let index = Int(identifier)!
		let displayedImage = batchImages[index]
		if let img = displayedImage.image {
			iv.image = img
		} else {
			displayedImage.image = imageCache?.imageWithId(displayedImage.imageId)
			iv.image = displayedImage.image
		}
		vc.view = iv
		return vc
	}
	
	func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?)
	{
		let iview = viewController.view as? NSImageView
		guard let dimg = object as? DisplayableImage else {
			iview?.image = nil
			return
		}
		if dimg.image == nil {
			dimg.image = imageCache?.imageWithId(dimg.imageId)
		}
		iview?.image = dimg.image
		labelField?.stringValue = dimg.name
	}
	
	func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
		pageController.completeTransition()
	}
}

class ImageViewController: NSViewController {
	var didAddConstraints = false
	override func viewWillAppear() {
		super.viewWillAppear()
		guard !didAddConstraints else { return }
		if let sv = view.superview, let ssv = sv.superview {
			ssv.addConstraint(view.widthAnchor.constraint(equalTo: sv.widthAnchor, multiplier: 1))
			ssv.addConstraint(view.heightAnchor.constraint(equalTo: sv.heightAnchor, multiplier: 1))
			ssv.addConstraint(view.centerXAnchor.constraint(equalTo: sv.centerXAnchor, constant: 0))
			ssv.addConstraint(view.centerYAnchor.constraint(equalTo: sv.centerYAnchor, constant: 0))
			ssv.needsLayout = true
			didAddConstraints = true
		}
	}
}
