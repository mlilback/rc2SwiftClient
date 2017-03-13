//
//  ImageCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Dispatch
import os
import Freddy
import ReactiveSwift

public enum ImageCacheError: Error, Rc2DomainError {
	case noSuchImage
	case failedToLoadFromNetwork
}

/// Handles caching of SessionImage(s)
public class ImageCache: JSONEncodable {
	///to allow dependency injection
	var fileManager: Foundation.FileManager
	///to allow dependency injection
	var workspace: Workspace?
	let restClient: Rc2RestClient
	///caching needs to be unique for each server. we don't care what the identifier is, just that it is unique per host
	///mutable because we need to be able to read it from an archive
	fileprivate(set) var hostIdentifier: String
	
	fileprivate var cache: NSCache<AnyObject, AnyObject>
	fileprivate var metaCache: [Int: SessionImage]
	
	fileprivate(set) lazy var cacheUrl: URL =
		{
			var result: URL?
			do {
				result = try AppInfo.subdirectory(type: .cachesDirectory, named: "\(self.hostIdentifier)/images")
			} catch let error as NSError {
				os_log("got error creating image cache direcctory: %{public}@", log: .cache, type:.error, error)
				assertionFailure("failed to create image cache dir")
			}
			return result!
		}()
	
	public static var supportsSecureCoding: Bool { return true }
	
	init(restClient: Rc2RestClient, fileManager fm: Foundation.FileManager=Foundation.FileManager(), hostIdentifier hostIdent: String)
	{
		self.restClient = restClient
		fileManager = fm
		cache = NSCache()
		metaCache = [:]
		hostIdentifier = hostIdent
	}
	
	/// loads cached data from json serialized by previous call to toJSON()
	///
	/// - Parameter json: the input json
	/// - Throws: json decoding errors
	public func load(from json: JSON) throws {
		self.hostIdentifier = try json.getString(at: "hostIdentifier")
		let images: [SessionImage] = try json.decodedArray(at: "images")
		images.forEach { metaCache[$0.id] = $0 }
	}
	
	/// serializes to a JSON that can be restored via load()
	///
	/// - Returns: data encoded as JSON
	public func toJSON() -> JSON {
		return .dictionary(["hostIdentifier": .string(hostIdentifier), "images": Array(metaCache.values).toJSON()])
	}
	
	func image(withId imageId: Int) -> PlatformImage? {
		if let pitem = cache.object(forKey: imageId as AnyObject) as? NSPurgeableData {
			defer { pitem.endContentAccess() }
			if pitem.beginContentAccess() {
				return PlatformImage(data: NSData(data: pitem as Data) as Data)
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
	public func cacheImageFromServer(_ img: SessionImage) {
		//cache to disk
		os_log("caching image %d", log: .cache, type: .info, img.id)
		let destUrl = URL(fileURLWithPath: "\(img.id).png", isDirectory: false, relativeTo: cacheUrl)
		try? img.imageData!.write(to: destUrl, options: [.atomic])
		//cache in memory
		let pdata = NSData(data: img.imageData! as Data) as Data
		cache.setObject(pdata as AnyObject, forKey: img.id as AnyObject)
		metaCache[img.id] = SessionImage(img)
	}
	
	func cacheImagesFromServer(_ images: [SessionImage]) {
		for anImage in images {
			cacheImageFromServer(anImage)
		}
	}
	
	public func sessionImages(forBatch batchId: Int) -> [SessionImage] {
		os_log("look for batch %d", log: .cache, type: .debug, batchId)
		var matches: [SessionImage] = []
		for anImage in metaCache.values {
			if anImage.batchId == batchId {
				matches.append(anImage)
			}
		}
		return matches.sorted(by: { $0.id < $1.id })
	}
	
	public func clearCache() {
		cache.removeAllObjects()
		metaCache.removeAll()
	}
	
	///imageWithId: should have been called at some point to make sure the image is cached
	public func urlForCachedImage(_ imageId: Int) -> URL {
		return URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: self.cacheUrl).absoluteURL
	}
	
	public func image(withId imageId: Int) -> SignalProducer<PlatformImage, ImageCacheError> {
		assert(workspace != nil, "imageCache.workspace must be set before using")
		let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: self.cacheUrl)
		return SignalProducer<PlatformImage, ImageCacheError>() { observer, _ in
			// swiftlint:disable:next force_try
			if try! fileUrl.checkResourceIsReachable() {
				observer.send(value: PlatformImage(contentsOf: fileUrl)!)
				observer.sendCompleted()
				return
			}
			//need to fetch from server
			let sp = self.restClient.downloadImage(imageId: imageId, from: self.workspace!, destination: fileUrl)
			sp.startWithResult { result in
				if let imgUrl = result.value, let pimg = PlatformImage(contentsOf: imgUrl) {
					observer.send(value: pimg)
					observer.sendCompleted()
				} else {
					observer.send(error: .failedToLoadFromNetwork)
				}
			}
		}
	}
}
