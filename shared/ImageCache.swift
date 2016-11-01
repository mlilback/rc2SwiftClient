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
import ClientCore
import BrightFutures
import Dispatch
import os

enum ImageCacheError: Error {
	case noSuchImage
	case failedToLoadFromNetwork
}

/// Handles caching of SessionImage(s)
/// implements NSSecureCoding so can be saved
open class ImageCache :NSObject, NSSecureCoding {
	///to allow dependency injection
	var fileManager:Foundation.FileManager
	///to allow dependency injection
	var workspace: Workspace?
	weak var restServer:RestServer?
	///caching needs to be unique for each server. we don't care what the identifier is, just that it is unique per host
	///mutable because we need to be able to read it from an archive
	fileprivate(set) var hostIdentifier: String
	
	fileprivate var cache: NSCache<AnyObject, AnyObject>
	fileprivate var metaCache: [Int:SessionImage]
	
	fileprivate(set) lazy var cacheUrl: URL =
		{
			var result: URL?
			do {
				let fm = self.fileManager
				let cacheDir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
				let ourDir = cacheDir.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory:true)
				let imgDir = ourDir.appendingPathComponent("\(self.hostIdentifier)/images", isDirectory: true)
				if !(imgDir as NSURL).checkResourceIsReachableAndReturnError(nil) {
					try self.fileManager.createDirectory(at: imgDir, withIntermediateDirectories: true, attributes: nil)
				}
				result = imgDir
			} catch let error as NSError {
				os_log("got error creating image cache direcctory: %{public}s", type:.error, error)
				assertionFailure("failed to create image cache dir")
			}
			return result!
		}()
	
	public static var supportsSecureCoding : Bool { return true }
	
	init(restServer:RestServer, fileManager fm:Foundation.FileManager=Foundation.FileManager(), hostIdentifier hostIdent:String) {
		self.restServer = restServer
		fileManager = fm
		cache = NSCache()
		metaCache = [:]
		hostIdentifier = hostIdent
	}
	
	public required init?(coder decoder:NSCoder) {
		guard let host = decoder.decodeObject(of: NSString.self, forKey: "hostIdentifier") as? String else {
			return nil
		}
		hostIdentifier = host
		fileManager = Foundation.FileManager.default
		cache = NSCache()
		metaCache = decoder.decodeObject(of: [NSArray.self, SessionImage.self, NSNumber.self], forKey: "metaCache") as! [Int:SessionImage]
	}
	
	open func encode(with coder: NSCoder) {
		coder.encode(hostIdentifier, forKey:"hostIdentifier")
		coder.encode(metaCache, forKey: "metaCache")
	}
	
	func imageWithId(_ imageId:Int) -> PlatformImage? {
		if let pitem = cache.object(forKey: imageId as AnyObject) {
			defer { pitem.endContentAccess() }
			if pitem.beginContentAccess() {
				return PlatformImage(data: NSData(data: (pitem as! NSPurgeableData) as Data) as Data)
			}
		}
		//read from disk
		let imgUrl = URL(fileURLWithPath: "\(imageId).png", relativeTo: cacheUrl)
		guard let imgData = try? Data(contentsOf: imgUrl) else {
			return nil
		}
		cache.setObject(NSPurgeableData(data: imgData), forKey: imageId as AnyObject)
		return PlatformImage(data: imgData)
	}
	
	///caches to disk and in memory
	func cacheImageFromServer(_ img:SessionImage) {
		//cache to disk
		let destUrl = URL(fileURLWithPath: "\(img.id).png", isDirectory: false, relativeTo: cacheUrl)
		try? img.imageData!.write(to: destUrl, options: [.atomic])
		//cache in memory
		let pdata = NSData(data: img.imageData! as Data) as Data
		cache.setObject(pdata as AnyObject, forKey: img.id as AnyObject)
		metaCache[img.id] = (img.copy() as! SessionImage)
	}
	
	func cacheImagesFromServer(_ images:[SessionImage]) {
		for anImage in images {
			cacheImageFromServer(anImage)
		}
	}
	
	func sessionImagesForBatch(_ batchId:Int) -> [SessionImage] {
		var matches:[SessionImage] = []
		for anImage in metaCache.values {
			if anImage.batchId == batchId {
				matches.append(anImage)
			}
		}
		return matches.sorted(by: { $0.id < $1.id })
	}
	
	func clearCache() {
		cache.removeAllObjects()
		metaCache.removeAll()
	}
	
	///imageWithId: should have been called at some point to make sure the image is cached
	func urlForCachedImage(_ imageId:Int) -> URL {
		return URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: self.cacheUrl).absoluteURL
	}
	
	func imageWithId(_ imageId:Int) -> Future<PlatformImage, ImageCacheError> {
		assert(workspace != nil, "imageCache.workspace must be set before using")
		let promise = Promise<PlatformImage, ImageCacheError>()
		let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: self.cacheUrl)
		DispatchQueue.global().async {
			do {
				if try fileUrl.checkResourceIsReachable() {
					promise.success(PlatformImage(contentsOf: fileUrl)!)
					return
				}
			} catch {
			}
			//need to fetch from server
			self.restServer!.downloadImage(self.workspace!, imageId: imageId, destination: fileUrl).onSuccess
			{ _ in
				if let pimg = PlatformImage(contentsOf: fileUrl) {
					return promise.success(pimg)
				}
				return promise.failure(.failedToLoadFromNetwork)
			}.onFailure() { err in
				promise.failure(.failedToLoadFromNetwork)
			}
		}
		return promise.future
	}
}
