//
//  DockerPullOperation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import SwiftyJSON

public struct LayerProgress {
	let id:String
	var finalSize: Int = 0
	var currentSize: Int = 0
	var complete: Bool = false
	
	init(layerId:String) {
		id = layerId
	}
}


public class DockerPullOperation: NSObject, NSURLSessionDataDelegate {
	private let url: NSURL
	private let urlConfig: NSURLSessionConfiguration
	private var urlSession: NSURLSession?
	private var _task: NSURLSessionDataTask?
	let promise = Promise<Bool, NSError>()
	var layers = [String:LayerProgress]()
	var totalDownloaded: Int = 0
	var statuses = Set<String>()
	
	/// - parameter baseUrl: the scheme/host/port to use for the connection
	/// - parameter imageName: the name of the image to pull
	/// - parameter config: sesion configuration to use. If nil, will use system default
	public init(baseUrl:NSURL, imageName:String, config:NSURLSessionConfiguration? = nil) {
		urlConfig = config ?? NSURLSessionConfiguration.defaultSessionConfiguration()
		let urlparts = NSURLComponents(URL: baseUrl, resolvingAgainstBaseURL: true)
		urlparts?.path = "/images/create"
		urlparts?.queryItems = [NSURLQueryItem(name:"fromImage", value: imageName)]
		self.url = urlparts!.URL!
	}
	
	public func start() {
		log.info("starting pull: \(url.absoluteString)")
		urlSession = NSURLSession(configuration: urlConfig, delegate: self, delegateQueue:NSOperationQueue.mainQueue())
		
		let req = NSMutableURLRequest(URL: url)
		req.HTTPMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField:"Content-Type")
		req.addValue("application/json", forHTTPHeaderField: "Accept")
		
		_task = urlSession!.dataTaskWithRequest(req)
		_task?.resume()
	}
	
	public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void)
	{
		completionHandler(NSURLSessionResponseDisposition.Allow)
	}

	public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
		let str = String(data: data, encoding:NSUTF8StringEncoding)!
		let json = JSON.parse(str)
		guard let status = json["status"].string else {
			log.info("invalid json chunk from pull")
			return
		}
		statuses.insert(status)
		switch status {
			case "Pulling fs layer":
				layers[json["id"].string!] = LayerProgress(layerId: json["id"].string!)
			case "Downloading":
				if var layer = layers[json["id"].stringValue] {
					if let details = json["progressDetails"].dictionary {
						if let fsize = details["total"]?.int where layer.finalSize == 0 {
							layer.finalSize = fsize
						}
						if let csize = details["curent"]?.int {
							layer.currentSize = csize
						}
					}
				}
			case "Download Complete":
				if var layer = layers[json["id"].stringValue] {
					log.info("finished layer \(layer.id)")
					layer.complete = true
					totalDownloaded += layer.finalSize
				}
			default:
				//log.info("ignoring \(json["status"].stringValue)")
				break
		}
	}
	
	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
		log.info("pull finished: \(totalDownloaded)")
		log.info("statuses=\(statuses)")
		guard nil == error else { promise.failure(error!); return }
		promise.success(true)
	}

}
