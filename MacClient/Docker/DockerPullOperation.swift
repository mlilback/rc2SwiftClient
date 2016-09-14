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
	let promise = Promise<Bool, NSError>()
	var layers = [String:LayerProgress]()
	var totalDownloaded: Int = 0
	var statuses = Set<String>()
	
	/// - parameter baseUrl: the scheme/host/port to use for the connection
	/// - parameter imageName: the name of the image to pull
	/// - parameter config: sesion configuration to use. If nil, will use system default
	public init(baseUrl:URL, imageName:String, config:URLSessionConfiguration? = nil) {
		urlConfig = config ?? URLSessionConfiguration.default
		var urlparts = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true)
		urlparts?.path = "/images/create"
		urlparts?.queryItems = [URLQueryItem(name:"fromImage", value: imageName)]
		self.url = urlparts!.url!
	}
	
	open func start() {
		os_log("starting pull: %{public}@", type:.info, url.absoluteString)
		urlSession = Foundation.URLSession(configuration: urlConfig, delegate: self, delegateQueue:OperationQueue.main)
		
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField:"Content-Type")
		req.addValue("application/json", forHTTPHeaderField: "Accept")
		
		_task = urlSession!.dataTask(with: req)
		_task?.resume()
	}
	
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}

	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let str = String(data: data, encoding:String.Encoding.utf8)!
		let json = JSON.parse(str)
		guard let status = json["status"].string else {
			os_log("invalid json chunk from pull", type:.info)
			return
		}
		statuses.insert(status)
		switch status {
			case "Pulling fs layer":
				layers[json["id"].string!] = LayerProgress(layerId: json["id"].string!)
			case "Downloading":
				if var layer = layers[json["id"].stringValue] {
					if let details = json["progressDetails"].dictionary {
						if let fsize = details["total"]?.int , layer.finalSize == 0 {
							layer.finalSize = fsize
						}
						if let csize = details["curent"]?.int {
							layer.currentSize = csize
						}
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
		os_log("statuses= %{public}@", type:.info, statuses)
		guard nil == error else { promise.failure(error! as NSError); return }
		promise.success(true)
	}

}
