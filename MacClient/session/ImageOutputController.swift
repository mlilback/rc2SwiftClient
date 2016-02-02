//
//  ImageOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CoreServices

//TODO: if splitter resizes us, the pagecontroller view does not adjust its frame
//TODO: figure out how to support async image loading
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
	@IBOutlet var imageView: NSImageView?
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
		pageController?.transitionStyle = .StackBook
		pageController?.view = imageView!
		shareButton?.sendActionOn(Int(NSEventMask.LeftMouseDownMask.rawValue))
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
	
	func displayImageAtIndex(index:Int, images:[SessionImage]) {
		batchImages = images.map { (simg) -> DisplayableImage in
			return DisplayableImage(imageId: simg.id, name: simg.name)
		}
		firstIndex = index
		pageController?.arrangedObjects = batchImages
		pageController?.selectedIndex = index
	}
	
	@IBAction func navigateClicked(sender:AnyObject?) {
		switch ((navigateButton?.selectedSegment)!) {
		case 0:
			pageController?.navigateBack(self)
		case 1:
			pageController?.navigateForward(self)
		default:
			break
		}
	}
	
	@IBAction func shareImage(sender:AnyObject?) {
		let dimg = batchImages[(pageController?.selectedIndex)!]
		let imgUrl = imageCache?.urlForCachedImage(dimg.imageId)
		myShareServices.removeAll()
		let wspace = NSWorkspace()
		if let appUrl = wspace.URLForApplicationToOpenURL(imgUrl!) {
			let appIcon = wspace.iconForFile(appUrl.path!)
			let appName = appUrl.localizedName()
			myShareServices.append(NSSharingService(title: "Open in \(appName)", image: appIcon, alternateImage: nil, handler: {
					var urlToUse = imgUrl!
					do {
						try urlToUse = NSFileManager.defaultManager().copyURLToTemporaryLocation(imgUrl!)
					} catch let err as NSError {
						log.error("error copying to tmp:\(err)")
					}
					wspace.openFile((urlToUse.path)!, withApplication: appUrl.path)
				}))
		}
		let picker = NSSharingServicePicker(items: [dimg.image!])
		picker.delegate = self
		picker.showRelativeToRect((shareButton?.bounds)!, ofView: shareButton!, preferredEdge: .MaxY)
	}
	
	func sharingServicePicker(sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [AnyObject], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService]
	{
		return myShareServices + proposedServices
	}
	
	func pageController(pageController: NSPageController, didTransitionToObject object: AnyObject) {
		if let dimage = object as? DisplayableImage {
			labelField?.stringValue = dimage.name
			let index = batchImages.indexOf(dimage)!
			navigateButton?.setEnabled(index > 0, forSegment: 0)
			navigateButton?.setEnabled(index < batchImages.count-1, forSegment: 1)
		}
	}
	
	func pageController(pageController: NSPageController, identifierForObject object: AnyObject) -> String {
		return "\(batchImages.indexOf(object as! DisplayableImage)!)"
	}
	
	func pageController(pageController: NSPageController, viewControllerForIdentifier identifier: String) -> NSViewController
	{
		let vc = NSViewController()
		let iv = NSImageView(frame: (imageView?.frame)!)
		iv.imageFrameStyle = .None
		let index = Int(identifier)!
		let displayedImage = batchImages[index]
		if displayedImage.image != nil {
			iv.image = displayedImage.image
		} else {
			displayedImage.image = imageCache?.imageWithId(displayedImage.imageId)
			iv.image = displayedImage.image
			//pagecontroller does not handle the image being specified after displaying the page/vc
//			imageCache?.imageWithId(displayedImage.imageId).onSuccess { nsimg in
//				displayedImage.image = nsimg
//				iv.image = nsimg
//				iv.needsDisplay = true
//				log.info("image \(displayedImage.name) loaded")
//				if self.firstIndex == index {
//					self.pageController?.selectedIndex = index
//				}
//			}.onFailure { error in
//				log.warning("error loading image \(displayedImage.imageId): \(error)")
//			}
		}
		vc.view = iv
		return vc
	}
	
	func pageControllerDidEndLiveTransition(pageController: NSPageController) {
		pageController.completeTransition()
	}
}

