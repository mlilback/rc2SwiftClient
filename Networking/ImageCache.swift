//
//  ImageCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Dispatch
import MJLLogger
import ReactiveSwift
import Model

public enum ImageCacheError: Error, Rc2DomainError {
	case noSuchImage
	case failedToLoadFromNetwork
}

/// Handles caching of SessionImage(s)
public class ImageCache {
	///to allow dependency injection
	var fileManager: Foundation.FileManager
	///to allow dependency injection
	var workspace: AppWorkspace?
	/// the client used to fetch images from the network
	let restClient: Rc2RestClient
	///caching needs to be unique for each server. we don't care what the identifier is, just that it is unique per host
	///mutable because we need to be able to read it from an archive
	fileprivate(set) var hostIdentifier: String
	
	fileprivate var cache: NSCache<AnyObject, AnyObject>
	fileprivate var metaCache: [Int: SessionImage]

	/// all cached images sorted in batches
	public let images: Property< [SessionImage] >
	
	private let _images: MutableProperty< [SessionImage] >
	
	fileprivate(set) lazy var cacheUrl: URL =
		{
			var result: URL?
			do {
				result = try AppInfo.subdirectory(type: .cachesDirectory, named: "\(self.hostIdentifier)/images")
			} catch let error as NSError {
				Log.error("got error creating image cache direcctory: \(error)", .cache)
				assertionFailure("failed to create image cache dir")
			}
			return result!
		}()
	
	public static var supportsSecureCoding: Bool { return true }
	
	init(restClient: Rc2RestClient, fileManager fm: Foundation.FileManager = Foundation.FileManager(), hostIdentifier hostIdent: String)
	{
		self.restClient = restClient
		fileManager = fm
		cache = NSCache()
		metaCache = [:]
		hostIdentifier = hostIdent
		_images = MutableProperty< [SessionImage] >([])
		images = Property< [SessionImage] >(capturing: _images)
	}
	
	/// loads cached data from json serialized by previous call to toJSON()
	///
	/// - Parameter sate: the state data to restore from
	/// - Throws: decoding errors
	public func restore(state: SessionState.ImageCacheState) throws {
		self.hostIdentifier = state.hostIdentifier
		state.images.forEach { metaCache[$0.id] = $0 }
		adjustImageArray()
	}
	
	/// serializes cache state
	///
	/// - Parameter state: where to save the state to
	public func save(state: inout SessionState.ImageCacheState) throws
	{
		state.hostIdentifier = hostIdentifier
		state.images = Array(metaCache.values)
	}
	
	/// Returns an image from the cache if it is in memory or on disk. returns nil if not in cache
	///
	/// - Parameter imageId: the id of the image to get
	/// - Returns: the image, or nil if there is no cached image with that id
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
	
	/// caches to disk and in memory
	private func cacheImageFromServer(_ img: SessionImage) {
		//cache to disk
		Log.info("caching image \(img.id)", .cache)
		let destUrl = URL(fileURLWithPath: "\(img.id).png", isDirectory: false, relativeTo: cacheUrl)
		try? img.imageData.write(to: destUrl, options: [.atomic])
		//cache in memory
		let pdata = NSData(data: img.imageData) as Data
		cache.setObject(pdata as AnyObject, forKey: img.id as AnyObject)
		metaCache[img.id] = img
	}
	
	/// Stores an array of SessionImage objects
	///
	/// - Parameter images: the images to save to the cache
	func cache(images: [SessionImage]) {
		images.forEach { cacheImageFromServer($0) }
		adjustImageArray()
	}
	
	/// Returns the images belonging to a particular batch
	///
	/// - Parameter batchId: the batch to get images for
	/// - Returns: an array of images
	public func sessionImages(forBatch batchId: Int) -> [SessionImage] {
		Log.debug("look for batch \(batchId)", .cache)
		return metaCache.values.filter({ $0.batchId == batchId }).sorted(by: { $0.id < $1.id })
	}
	
	/// Removes all images from the in-memory cache
	public func clearCache() {
		cache.removeAllObjects()
		metaCache.removeAll()
		_images.value = []
	}
	
	/// image(withId:) should have been called at some point to make sure the image is cached
	public func urlForCachedImage(_ imageId: Int) -> URL {
		return URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: self.cacheUrl).absoluteURL
	}
	
	/// Loads an image from memory, disk, or the network based on if it is cached
	public func image(withId imageId: Int) -> SignalProducer<PlatformImage, ImageCacheError> {
		assert(workspace != nil, "imageCache.workspace must be set before using")
		let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: self.cacheUrl)
		return SignalProducer<PlatformImage, ImageCacheError> { observer, _ in
			// swiftlint:disable:next force_try
			if try! fileUrl.checkResourceIsReachable() {
				observer.send(value: PlatformImage(contentsOf: fileUrl)!)
				observer.sendCompleted()
				return
			}
			//need to fetch from server
			let sp = self.restClient.downloadImage(imageId: imageId, from: self.workspace!, destination: fileUrl)
			sp.startWithResult { result in
				if case .success(let imgUrl) = result, let pimg = PlatformImage(contentsOf: imgUrl) {
					observer.send(value: pimg)
					observer.sendCompleted()
				} else {
					observer.send(error: .failedToLoadFromNetwork)
				}
			}
		}
	}
	
	/// reset the images property grouped by batch
	private func adjustImageArray() {
		_images.value = metaCache.values.sorted { img1, img2 in
			guard img1.batchId == img2.batchId else { return img1.batchId < img2.batchId }
			//using id because we know they are in proper order, might be created too close together to use dateCreated
			return img1.id < img2.id
		}
	}
}
