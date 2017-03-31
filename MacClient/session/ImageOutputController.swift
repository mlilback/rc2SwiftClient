//
//  ImageOutputController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import CoreServices
import os
import ReactiveSwift
import Networking

//class DisplayableImage: NSObject {
//	let imageId: Int
//	let name: String
//	var image: NSImage?
//
//	init(imageId: Int, name: String) {
//		self.imageId = imageId
//		self.name = name
//	}
//
//	convenience init(_ simage: SessionImage) {
//		self.init(imageId: simage.id, name: simage.displayName)
//	}
//}

class ImageOutputController: NSViewController, OutputController, NSPageControllerDelegate, NSSharingServicePickerDelegate {
	let emptyIdentifier = "empty"
	
	@IBOutlet var containerView: NSView?
	@IBOutlet var imagePopup: NSPopUpButton?
	@IBOutlet var shareButton: NSSegmentedControl?
	@IBOutlet var navigateButton: NSSegmentedControl?

	var pageController: NSPageController!
	var allImages: MutableProperty< [SessionImage] >?
	var imageCache: ImageCache? { didSet { imageCacheChanged() } }
	var myShareServices: [NSSharingService] = []
	fileprivate var selectedImage: SessionImage?
	fileprivate let emptyObject: Any = 1 as Any
	
	override func viewDidLoad() {
		super.viewDidLoad()
		pageController = NSPageController()
		pageController.delegate = self
		pageController.transitionStyle = .stackBook
		pageController.view = containerView!
		// for some reason, the selected controller's view's frame is not correct. This fixes it, even though there is probably a more efficent way to fix this
		pageController.view.postsFrameChangedNotifications = true
		NotificationCenter.default.addObserver(forName: .NSViewFrameDidChange, object: nil, queue: nil) { [weak self] _ in
			guard let pc = self?.pageController, pc.view.frame.size != pc.selectedViewController?.view.frame.size else { return }
			let newFrame = NSRect(origin: .zero, size: pc.view.frame.size)
			pc.selectedViewController?.view.frame = newFrame
		}

		view.wantsLayer = true
		shareButton?.sendAction(on: NSEventMask(rawValue: UInt64(Int(NSEventMask.leftMouseDown.rawValue))))
		view.layer?.backgroundColor = PlatformColor.white.cgColor
		navigateButton?.setEnabled(false, forSegment: 0)
		navigateButton?.setEnabled(false, forSegment: 1)
		guard let allImages = allImages else { fatalError("images not loaded properly") }
		guard allImages.value.count > 0 else {
			displayEmptyView()
			return
		}
		pageController.arrangedObjects = allImages.value
		if nil == selectedImage { selectedImage = allImages.value.first }
		loadSelectedImage()
		pageController.selectedIndex = allImages.value.index(of: selectedImage!) ?? 0
		imagePopup?.selectItem(withTag: selectedImage?.id ?? 0)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		pageController.view.needsLayout = true
		pageController.view.needsDisplay = true
		pageController.selectedViewController?.view.needsLayout = true
		pageController.selectedViewController?.view.needsDisplay = true
	}

	func imageCacheChanged() {
		guard let icache = imageCache else { return }
		if allImages == nil {
			allImages = MutableProperty([])
			allImages! <~ icache.images
			allImages?.signal.observeValues { [weak self] _ in
				self?.imageArrayChanged()
				self?.adjustImagePopup()
			}
		}
	}
	
	func imageArrayChanged() {
		//if there are no images, we don't have a selection and should show empty view
		guard let all = allImages?.value, all.count > 0 else {
			selectedImage = nil
			displayEmptyView()
			return
		}
		//if for some reason the selected image isn't in the images array, discard the selection
		if let selImage = selectedImage, !all.contains(selImage) {
			selectedImage = nil
		}
		//if no selection, select first image
		if selectedImage == nil {
			selectedImage = all.first
		}
		loadSelectedImage()
	}
	
	func display(image: SessionImage) {
		selectedImage = image
		guard isViewLoaded else { return }
		loadSelectedImage()
	}
	
	fileprivate func loadSelectedImage() {
		guard let allImages = allImages else { fatalError("invalid call to loadSelectedImages") }
		guard let image = selectedImage, let index = allImages.value.index(of: image) else {
			os_log("asked to display image when none are in cache")
			displayEmptyView()
			return
		}
		pageController?.arrangedObjects = allImages.value
		pageController?.selectedIndex = index
		navigateButton?.setEnabled(index > 0, forSegment: 0)
		navigateButton?.setEnabled(index + 1 < allImages.value.count, forSegment: 1)
		imagePopup?.isEnabled = true
		imagePopup?.selectItem(withTag: image.id)
	}
	
	fileprivate func displayEmptyView() {
		guard isViewLoaded else { return }
		pageController.arrangedObjects = [emptyObject]
		pageController.selectedIndex = 0
		navigateButton?.setEnabled(false, forSegment: 0)
		navigateButton?.setEnabled(false, forSegment: 1)
		imagePopup?.isEnabled = false
	}
	
	@IBAction func navigateClicked(_ sender: AnyObject?) {
		switch (navigateButton?.selectedSegment)! {
		case 0:
			pageController?.navigateBack(self)
		case 1:
			pageController?.navigateForward(self)
		default:
			break
		}
	}
	
	@IBAction func shareImage(_ sender: AnyObject?) {
		guard let img = selectedImage else { fatalError("shouldn't be able to share w/o an image") }
		let imgUrl = imageCache?.urlForCachedImage(img.id)
		myShareServices.removeAll()
		let wspace = NSWorkspace()
		if let appUrl = wspace.urlForApplication(toOpen: imgUrl!) {
			let appIcon = wspace.icon(forFile: appUrl.path)
			let appName = appUrl.localizedName()
			myShareServices.append(NSSharingService(title: "Open in \(appName)", image: appIcon, alternateImage: nil, handler: {
					var urlToUse = imgUrl!
					do {
						let fm = Rc2DefaultFileManager()
						try urlToUse = fm.copyURLToTemporaryLocation(imgUrl!)
					} catch let err as NSError {
						os_log("error copying to tmp: %{public}@", log: .app, type: .error, err)
					}
					wspace.openFile(urlToUse.path, withApplication: appUrl.path)
				}))
		}
		imageCache?.image(withId: img.id).observe(on: UIScheduler()).startWithResult { result in
			let picker = NSSharingServicePicker(items: [result.value!])
			picker.delegate = self
			picker.show(relativeTo: (self.shareButton?.bounds)!, of: self.shareButton!, preferredEdge: .maxY)
		}
	}

	// load the images into the popup
	func adjustImagePopup() {
		imagePopup?.removeAllItems()
		guard let images = allImages?.value, images.count > 0 else { return }
		var currentBatch = images[0].batchId
		for anImage in images {
			if anImage.batchId != currentBatch {
				imagePopup?.menu?.addItem(NSMenuItem.separator())
				currentBatch = anImage.batchId
			}
			let item = NSMenuItem(title: anImage.displayName, action: #selector(selectImage(_:)), keyEquivalent: "")
			item.tag = anImage.id
			item.target = self
			item.toolTip = anImage.name
			item.representedObject = anImage
			imagePopup?.menu?.addItem(item)
		}
	}
	
	func selectImage(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem, let image = menuItem.representedObject as? SessionImage else { return }
		display(image: image)
	}
	
	func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService]
	{
		return myShareServices + proposedServices
	}
	
	func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
		guard let img = object as? SessionImage, let allImages = allImages else {
			os_log("page controller switched to non-existant image")
			displayEmptyView()
			return
		}
		selectedImage = img
		imagePopup?.selectItem(withTag: img.id)
		let index = allImages.value.index(of: img)!
		navigateButton?.setEnabled(index > 0, forSegment: 0)
		navigateButton?.setEnabled(index < allImages.value.count - 1, forSegment: 1)
	}
	
	func pageController(_ pageController: NSPageController, identifierFor object: Any) -> String {
		guard let image = object as? SessionImage else { return emptyIdentifier }
		return "\(image.id)"
	}
	
	func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: String) -> NSViewController
	{
		let vc = ImageViewController()
		let iv = NSImageView(frame: (containerView?.frame)!)
		iv.imageFrameStyle = .none
		iv.setContentHuggingPriority(200, for: .horizontal)
		iv.setContentCompressionResistancePriority(200, for: .horizontal)
		iv.imageScaling = .scaleProportionallyDown
		if let imageId = Int(identifier) {
			vc.setImage(producer: imageCache!.image(withId: imageId))
		}
		vc.view = iv
		return vc
	}
	
	func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect {
		return NSRect(origin: NSPoint.zero, size: pageController.view.frame.size)
	}
	
	func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?)
	{
		guard let myViewController = viewController as? ImageViewController else { return }
		guard let img = object as? SessionImage else {
			myViewController.setImage(image: nil)
			return
		}
		myViewController.setImage(producer: imageCache!.image(withId: img.id))
	}
	
	func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
		pageController.completeTransition()
	}
}

class ImageViewController: NSViewController {
	var didAddConstraints = false
	var imageLoadDisposable: Disposable?
	
	var imageView: NSImageView? { return view as? NSImageView }
	
	//starting with sierra, all viewcontrollers must have a view after this call. We setup a dummy one that will be replaced by our parent controller
	override func loadView() {
		self.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
	}
	
	func setImage(image: NSImage?) {
		imageLoadDisposable = nil
		imageView?.image = image
	}
	
	func setImage(producer: SignalProducer<PlatformImage, ImageCacheError>) {
		imageLoadDisposable?.dispose() //dispose of any currently loading image
		producer.startWithResult { result in
			guard let newImage = result.value else {
				os_log("failed to load image: %{public}@", log: .app, result.error!.localizedDescription)
				return
			}
			self.imageLoadDisposable = nil
			self.imageView?.image = newImage
		}
	}
}
