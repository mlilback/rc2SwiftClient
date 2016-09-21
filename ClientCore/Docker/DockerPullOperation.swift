//
//  DockerPullOperation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import SwiftyJSON
import os

//progress information on the pull
public struct PullProgress {
	public let name:String
	public let estSize:Int64
	public var currentSize:Int64 = 0
	public var extracting:Bool = false
	public var complete:Bool = false
	
	public init(name:String, size:Int64) {
		self.name = name
		self.estSize = size
	}
}

//represents the status as a layer is downloaded
struct LayerProgress {
	let id:String
	var finalSize: Int = 0
	var currentSize: Int = 0
	var complete: Bool = false
	
	init(layerId:String) {
		id = layerId
	}
}

public typealias PullProgressHandler = (PullProgress) -> Void

open class DockerPullOperation: NSObject, URLSessionDataDelegate {
	fileprivate let url: URL
	fileprivate let urlConfig: URLSessionConfiguration
	fileprivate var urlSession: Foundation.URLSession?
	fileprivate var _task: URLSessionDataTask?
	fileprivate var _progressHandler:PullProgressHandler?
	fileprivate(set) var pullProgress: PullProgress
	fileprivate var _lastUpdate: Double = 0
	let estimatedSize: Int64
	let promise = Promise<Bool, NSError>()
	var layers = [String:LayerProgress]()
	var totalDownloaded: Int64 = 0
	var statuses = Set<String>()
	
	/// - parameter baseUrl: the scheme/host/port to use for the connection
	/// - parameter imageName: the name of the image to pull
	/// - parameter estimatedSize: the size of the download, used for progress calculation
	/// - parameter config: sesion configuration to use. If nil, will use system default
	public init(baseUrl:URL, imageName:String, estimatedSize size:Int64, config:URLSessionConfiguration? = nil) {
		urlConfig = config ?? URLSessionConfiguration.default
		var urlparts = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true)
		urlparts?.path = "/images/create"
		urlparts?.queryItems = [URLQueryItem(name:"fromImage", value: imageName)]
		self.url = urlparts!.url!
		self.estimatedSize = size
		pullProgress = PullProgress(name: imageName, size: size)
	}
	
	open func startPull(progressHandler:@escaping PullProgressHandler) -> Future<Bool, NSError> {
		_progressHandler = progressHandler
		os_log("starting pull: %{public}s", type:.info, url.absoluteString)
		urlSession = Foundation.URLSession(configuration: urlConfig, delegate: self, delegateQueue:OperationQueue.main)
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField:"Content-Type")
		req.addValue("application/json", forHTTPHeaderField: "Accept")
		
		_task = urlSession!.dataTask(with: req)
		_task?.resume()
		return promise.future
	}
	
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}

	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let oldTotal = totalDownloaded
		let str = String(data: data, encoding:String.Encoding.utf8)!
		let messages = str.components(separatedBy: "\r\n")
		for aMessage in messages {
			guard aMessage.characters.count > 0 else { continue }
			let json = JSON.parse(aMessage)
			guard let status = json["status"].string else {
				os_log("invalid json chunk from pull %{public}s", type:.info, aMessage)
				continue
			}
			statuses.insert(status)
			handleStatus(status: status, json: json)
		}
		let curTime = Date.timeIntervalSinceReferenceDate
		if oldTotal == 0 || (curTime - _lastUpdate) > 0.1 {
			if totalDownloaded > oldTotal {
				pullProgress.currentSize = totalDownloaded
				os_log("downloaded: %d",type:.debug,  totalDownloaded)
				_progressHandler?(pullProgress)
			} else if totalDownloaded >= estimatedSize {
				pullProgress.extracting = true
				_progressHandler?(pullProgress)
			}
			_lastUpdate = curTime
		}
	}
	
	func handleStatus(status:String, json:JSON) {
		switch status {
			case "Pulling fs layer":
				layers[json["id"].string!] = LayerProgress(layerId: json["id"].string!)
			case "Downloading":
				if var layer = layers[json["id"].stringValue] {
					if let details = json["progressDetail"].dictionary {
						if let fsize = details["total"]?.int , layer.finalSize == 0 {
							NSLog("layer %@ is %d in size", layer.id, fsize)
							layer.finalSize = fsize
						}
						if let csize = details["current"]?.int {
							layer.currentSize = csize
						}
					}
					layers[layer.id] = layer
					totalDownloaded = layers.reduce(0) { cnt, layerTuple in
						return cnt + layerTuple.1.currentSize
					}
				}
			case "Download Complete":
				if var layer = layers[json["id"].stringValue] {
					os_log("finished layer %{public}@", type:.info, layer.id)
					layer.complete = true
					totalDownloaded += layer.finalSize
				}
			default:
				//log.info("ignoring \(json["status"].stringValue)")
				break
		}
	}
	
	open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		os_log("pull finished: %d", type:.info, totalDownloaded)
		pullProgress.complete = true
		guard nil == error else { promise.failure(error! as NSError); return }
		promise.success(true)
		for aLayer in layers.values {
			os_log("layer %{public}s is %d", type:.info, aLayer.id, aLayer.finalSize)
		}
	}

}
