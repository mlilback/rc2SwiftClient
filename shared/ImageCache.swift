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
	}
	
	func imageWithId(imageId:Int) -> Future<Image, ImageCacheError> {
		let promise = Promise<Image, ImageCacheError>()
		Queue.global.async {
			let fileUrl = NSURL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeToURL: self.cacheUrl)
			if fileUrl.checkResourceIsReachableAndReturnError(nil) {
				promise.success(Image(contentsOfURL: fileUrl)!)
			}
		}
		//need to fetch from server
		return promise.future
	}
}
