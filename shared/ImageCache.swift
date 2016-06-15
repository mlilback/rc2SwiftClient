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
	case FailedToLoadFromNetwork
}

/// Handles caching of SessionImage(s)
/// implements NSSecureCoding so can be saved
public class ImageCache :NSObject, NSSecureCoding {
	///to allow dependency injection
	var fileManager:NSFileManager
	var workspace: Workspace?
	
	private var cache: NSCache
	private var metaCache: [Int:SessionImage]
	
	private(set) lazy var cacheUrl: NSURL =
		{
			var result: NSURL?
			do {
				let fm = self.fileManager
				let baseDir = try fm.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
				let imgDirUrl = NSURL(fileURLWithPath: "Rc2/images/", isDirectory: true, relativeToURL: baseDir).absoluteURL
				try fm.createDirectoryAtURL(imgDirUrl, withIntermediateDirectories:true, attributes:nil)
				imgDirUrl.checkResourceIsReachableAndReturnError(nil) //throws instead of returning error
				result = imgDirUrl
			} catch let error {
				log.error("got error creating image cache direcctory:\(error)")
				assertionFailure("failed to create response handler")
			}
			return result!
		}()
	
	public static func supportsSecureCoding() -> Bool { return true }
	
	init(_ fm:NSFileManager=NSFileManager()) {
		fileManager = fm
		cache = NSCache()
		metaCache = [:]
	}
	
	public required init?(coder decoder:NSCoder) {
		fileManager = NSFileManager.defaultManager()
		cache = NSCache()
		metaCache = decoder.decodeObjectOfClasses([NSArray.self, SessionImage.self, NSNumber.self], forKey: "metaCache") as! [Int:SessionImage]
	}
	
	public func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(metaCache, forKey: "metaCache")
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
		img.imageData!.writeToURL(destUrl, atomically: true)
		//cache in memory
		let pdata = NSPurgeableData(data: img.imageData!)
		cache.setObject(pdata, forKey: img.id)
		metaCache[img.id] = (img.copy() as! SessionImage)
	}
	
	func cacheImagesFromServer(images:[SessionImage]) {
		for anImage in images {
			cacheImageFromServer(anImage)
		}
	}
	
	func sessionImagesForBatch(batchId:Int) -> [SessionImage] {
		var matches:[SessionImage] = []
		for anImage in metaCache.values {
			if anImage.batchId == batchId {
				matches.append(anImage)
			}
		}
		return matches.sort({ $0.id < $1.id })
	}
	
	func clearCache() {
		cache.removeAllObjects()
		metaCache.removeAll()
	}
	
	///imageWithId: should have been called at some point to make sure the image is cached
	func urlForCachedImage(imageId:Int) -> NSURL {
		return NSURL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeToURL: self.cacheUrl).absoluteURL
	}
	
	func imageWithId(imageId:Int) -> Future<PlatformImage, ImageCacheError> {
		assert(workspace != nil, "imageCache.workspace must be set before using")
		let promise = Promise<PlatformImage, ImageCacheError>()
		let fileUrl = NSURL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeToURL: self.cacheUrl)
		Queue.global.async {
			if fileUrl.checkResourceIsReachableAndReturnError(nil) {
				promise.success(PlatformImage(contentsOfURL: fileUrl)!)
				return
			}
			//need to fetch from server
			RestServer.sharedInstance.downloadImage(self.workspace!, imageId: imageId, destination: fileUrl).onSuccess
			{ _ in
				if let pimg = PlatformImage(contentsOfURL: fileUrl) {
					return promise.success(pimg)
				}
				return promise.failure(.FailedToLoadFromNetwork)
			}.onFailure() { err in
				promise.failure(.FailedToLoadFromNetwork)
			}
		}
		return promise.future
	}
}
