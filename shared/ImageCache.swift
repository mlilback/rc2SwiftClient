//
//  ImageCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

#if os(OSX)
	import Cocoa
#else
	import UIKit
#endif
import BrightFutures

enum ImageCacheError: ErrorType {
	case NoSuchImage
}

class ImageCache {
	///to allow dependency injection
	var fileManager:NSFileManager
	
	private var cache: NSCache
	
	lazy var cacheUrl: NSURL =
		{
			var result: NSURL?
			do {
				let fm = self.fileManager
				let baseDir = try fm.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
				let imgDirUrl = NSURL(fileURLWithPath: "Rc2/images", isDirectory: true, relativeToURL: baseDir)
				imgDirUrl.checkResourceIsReachableAndReturnError(nil) //throws instead of returning error
				result = imgDirUrl
			} catch let error {
				log.error("got error creating image cache direcctory:\(error)")
				assertionFailure("failed to create response handler")
			}
			return result!
		}()
	
	init(_ fm:NSFileManager=NSFileManager()) {
		fileManager = fm
		cache = NSCache()
	}
	
	func imageWithId(imageId:Int) -> PlatformImage? {
		if let pitem = cache.objectForKey(imageId) {
			defer { pitem.endContentAccess() }
			if pitem.beginContentAccess() {
				return PlatformImage(data: NSData(data: pitem as! NSPurgeableData))
			}
		}
		//read from disk
		let imgUrl = NSURL(fileURLWithPath: "\(imageId).png", relativeToURL: cacheUrl)
		guard let imgData = NSData(contentsOfURL: imgUrl) else {
			return nil
		}
		cache.setObject(NSPurgeableData(data: imgData), forKey: imageId)
		return PlatformImage(data: imgData)
	}
	
	///caches to disk and in memory
	func cacheImageFromServer(img:SessionImage) {
		//cache to disk
		let destUrl = NSURL(fileURLWithPath: "\(img.id).png", isDirectory: false, relativeToURL: cacheUrl)
		img.imageData.writeToURL(destUrl, atomically: true)
		//cache in memory
		let pdata = NSPurgeableData(data: img.imageData)
		cache.setObject(pdata, forKey: img.id)
	}
	
	func cacheImagesFromServer(images:[SessionImage]) {
		for anImage in images {
			cacheImageFromServer(anImage)
		}
	}
	
	func imageWithId(imageId:Int) -> Future<PlatformImage, ImageCacheError> {
		let promise = Promise<PlatformImage, ImageCacheError>()
		Queue.global.async {
			let fileUrl = NSURL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeToURL: self.cacheUrl)
			if fileUrl.checkResourceIsReachableAndReturnError(nil) {
				promise.success(PlatformImage(contentsOfURL: fileUrl)!)
			}
		}
		//need to fetch from server
		return promise.future
	}
}
