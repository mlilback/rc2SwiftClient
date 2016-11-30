//
//  DockerPullOperation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Freddy
import os
import ClientCore

///progress information on the pull
public struct PullProgress {
	///the name of the pull
	public let name: String
	///the estimated size used for progress calcuations
	public let estSize: Int64
	///the number of bytes downloaded so far
	public var currentSize: Int64 = 0
	///true if currently extracting the download
	public var extracting: Bool = false
	public var complete: Bool = false

	public init(name: String, size: Int64) {
		self.name = name
		self.estSize = size
	}
}

//represents the status as a layer is downloaded
struct LayerProgress {
	let id: String
	var finalSize: Int = 0
	var currentSize: Int = 0
	var complete: Bool = false

	init(layerId: String) {
		id = layerId
	}
}

public final class DockerPullOperation: NSObject, URLSessionDataDelegate {
	fileprivate let url: URL
	fileprivate let urlConfig: URLSessionConfiguration
	fileprivate var urlSession: Foundation.URLSession?
	fileprivate var _task: URLSessionDataTask?
	fileprivate(set) var pullProgress: PullProgress
	fileprivate var _lastUpdate: Double = 0
	let estimatedSize: Int64
	var layers = [String:LayerProgress]()
	var totalDownloaded: Int64 = 0
	var statuses = Set<String>()
	fileprivate var pullObserver: Signal<PullProgress, DockerError>.Observer?

	/// - parameter baseUrl: the scheme/host/port to use for the connection
	/// - parameter imageName: the name of the image to pull
	/// - parameter estimatedSize: the size of the download, used for progress calculation
	/// - parameter config: sesion configuration to use. If nil, will use system default
	public init(baseUrl: URL, imageName: String, estimatedSize size: Int64, config: URLSessionConfiguration) {
		let uconfig = config
		uconfig.timeoutIntervalForRequest = 300
		uconfig.timeoutIntervalForResource = 86400
		urlConfig = uconfig
		var urlparts = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true)
		urlparts?.path = "/images/create"
		urlparts?.queryItems = [URLQueryItem(name:"fromImage", value: imageName)]
		self.url = urlparts!.url!
		self.estimatedSize = size
		pullProgress = PullProgress(name: imageName, size: size)
		super.init()
		assert(urlConfig.protocolClasses!.filter({ $0 == DockerUrlProtocol.self }).count > 0)
	}

	public func pull() -> SignalProducer<PullProgress, DockerError> {
		return SignalProducer<PullProgress, DockerError>() { observer, _ in
			os_log("starting pull: %{public}@", type:.info, self.url.absoluteString)
			self.pullObserver = observer
			self.urlSession = Foundation.URLSession(configuration: self.urlConfig, delegate: self, delegateQueue:OperationQueue.main)
			var req = URLRequest(url: self.url)
			req.httpMethod = "POST"
			req.addValue("application/json", forHTTPHeaderField:"Content-Type")
			req.addValue("application/json", forHTTPHeaderField: "Accept")
			req.isChunkedResponse = true
			self._task = self.urlSession!.dataTask(with: req)
			self._task?.resume()
		}
	}
	
	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let oldTotal = totalDownloaded
		let str = String(data: data, encoding:String.Encoding.utf8)!
		let messages = str.components(separatedBy: "\r\n")
		for aMessage in messages {
			guard aMessage.characters.count > 0 else { continue }
			guard let json = try? JSON(jsonString: aMessage) else {
				os_log("invalid json chunk: %{public}@", type: .info, aMessage)
				continue
			}
			guard let status = try? json.getString(at: "status") else {
				os_log("invalid json chunk from pull %{public}@", type: .info, aMessage)
				continue
			}
			statuses.insert(status)
			handleStatus(status: status, json: json)
		}
		let curTime = Date.timeIntervalSinceReferenceDate
		if oldTotal == 0 || (curTime - _lastUpdate) > 0.1 {
			if totalDownloaded > oldTotal {
				pullProgress.currentSize = totalDownloaded
				pullObserver?.send(value: pullProgress)
			} else if totalDownloaded >= estimatedSize {
				pullProgress.extracting = true
				pullObserver?.send(value: pullProgress)
			}
			_lastUpdate = curTime
		}
	}

	func handleStatus(status: String, json: JSON) {
		guard let layerId = try? json.getString(at: "id") else { return }
		switch status.lowercased() {
			case "pulling fs layer":
				layers[layerId] = LayerProgress(layerId: layerId)
			case "downloading":
				if var layer = layers[layerId] {
					if let fsize = try? json.getInt(at: "progressDetail", "total"), layer.finalSize == 0 {
						layer.finalSize = fsize
					}
					if let csize = try? json.getInt(at: "progressDetail", "current") {
						layer.currentSize = csize
					}
					layers[layerId] = layer
					totalDownloaded = layers.reduce(0) { cnt, layerTuple in
						return cnt + layerTuple.1.currentSize
					}
				}
			case "download complete":
				if var layer = layers[layerId] {
					os_log("finished layer %{public}@", log: .docker, type:.info, layer.id)
					layer.complete = true
					totalDownloaded += layer.finalSize
				}
			default:
				//log.info("ignoring \(json["status"].stringValue)")
				break
		}
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard nil == error else {
			os_log("error in pull operation %{public}@", log: .docker, type: .debug, error! as NSError)
			pullObserver?.send(error: DockerError.cocoaError(error as NSError?))
			return
		}
		os_log("pull %{public}s finished: %d", log: .docker, type:.info, pullProgress.name, totalDownloaded)
		pullProgress.currentSize = totalDownloaded
		pullProgress.complete = true
		pullObserver?.send(value: pullProgress)
		pullObserver?.sendCompleted()
		for aLayer in layers.values {
			os_log("layer %{public}@ is %d", log: .docker, type:.info, aLayer.id, aLayer.finalSize)
		}
	}

}
