//
//  DockerPullOperation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import SwiftyJSON
import os

public struct LayerProgress {
	let id:String
	var finalSize: Int = 0
	var currentSize: Int = 0
	var complete: Bool = false
	
	init(layerId:String) {
		id = layerId
	}
}


open class DockerPullOperation: NSObject, URLSessionDataDelegate {
	fileprivate let url: URL
	fileprivate let urlConfig: URLSessionConfiguration
	fileprivate var urlSession: Foundation.URLSession?
	fileprivate var _task: URLSessionDataTask?
	fileprivate var _progressHandler:ProgressHandler?
	fileprivate(set) var progress: Progress?
	fileprivate var _lastUpdate: Double = 0
	let estimatedSize: Int64
	let promise = Promise<Bool, NSError>()
	var layers = [String:LayerProgress]()
	var totalDownloaded: Int = 0
	var statuses = Set<String>()
	
	/// - parameter baseUrl: the scheme/host/port to use for the connection
	/// - parameter imageName: the name of the image to pull
	/// - parameter config: sesion configuration to use. If nil, will use system default
	public init(baseUrl:URL, imageName:String, estimatedSize size:Int, config:URLSessionConfiguration? = nil) {
		urlConfig = config ?? URLSessionConfiguration.default
		var urlparts = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true)
		urlparts?.path = "/images/create"
		urlparts?.queryItems = [URLQueryItem(name:"fromImage", value: imageName)]
		self.url = urlparts!.url!
		self.estimatedSize = Int64(size)
		progress = Progress(totalUnitCount: estimatedSize)
	}
	
	open func startPull(progressHandler:ProgressHandler? = nil) -> Future<Bool, NSError> {
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
		if oldTotal == 0 || (totalDownloaded > oldTotal && (curTime - _lastUpdate) > 100) {
			//adjust progress
			os_log("downloaded: %d", totalDownloaded)
			progress?.completedUnitCount = Int64(totalDownloaded)
			_lastUpdate = curTime
			_progressHandler?(progress!)
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
		os_log("statuses= %{public}s", type:.info, statuses)
		progress?.completedUnitCount = (progress?.totalUnitCount)!
		guard nil == error else { promise.failure(error! as NSError); return }
		promise.success(true)
	}

}
