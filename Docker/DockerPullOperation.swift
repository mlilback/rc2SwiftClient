//
//  DockerPullOperation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Freddy
import os

///progress information on the pull
public struct PullProgress {
	///the name of the pull
	public let name: String
	///the estimated size used for progress calcuations
	public let estSize: Int
	///the number of bytes downloaded so far
	public var currentSize: Int = 0
	///true if currently extracting the download
	public var extracting: Bool = false
	public var complete: Bool = false

	public init(name: String, size: Int) {
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

public final class DockerPullOperation {
//	private let url: URL
	private let imageName: String
	private var connection: LocalDockerConnection!
	private(set) var pullProgress: PullProgress
	private var _lastUpdate: Double = 0
	let estimatedSize: Int
	var layers = [String: LayerProgress]()
	var totalDownloaded: Int = 0
	var statuses = Set<String>()
	private var pullObserver: Signal<PullProgress, DockerError>.Observer?

	/// - parameter imageName: the name of the image to pull
	/// - parameter estimatedSize: the size of the download, used for progress calculation
	public init(imageName: String, estimatedSize: Int) {
		self.imageName = imageName
		self.estimatedSize = estimatedSize
		var urlparts = URLComponents()
		urlparts.scheme = "dockerstream"
		urlparts.host = "localhost"
		urlparts.path = "/images/create"
		urlparts.queryItems = [URLQueryItem(name:"fromImage", value: imageName)]
		var request = URLRequest(url: urlparts.url!)
		request.httpMethod = "POST"
		pullProgress = PullProgress(name: imageName, size: estimatedSize)
		connection = LocalDockerConnectionImpl<HijackedResponseHandler>(request: request, handler: messageHandler)
	}
	
	private func messageHandler(message: LocalDockerMessage) {
		switch message {
		case .headers(_):
			break //we don't care
		case .error(let error):
			os_log("error in pull operation %{public}@", log: .docker, type: .debug, error as NSError)
			pullObserver?.send(error: error)
		case .data(let data):
			handle(data: data)
		case .complete:
			os_log("pull %{public}@ finished: %d", log: .docker, type:.info, pullProgress.name, totalDownloaded)
			pullProgress.currentSize = totalDownloaded
			if pullProgress.currentSize == 0 { pullProgress.currentSize = pullProgress.estSize }
			pullProgress.complete = true
			pullObserver?.send(value: pullProgress)
			pullObserver?.sendCompleted()
			for aLayer in layers.values {
				os_log("layer %{public}@ is %d", log: .docker, type:.info, aLayer.id, aLayer.finalSize)
			}
		}
	}
	
	public func pull() -> SignalProducer<PullProgress, DockerError>
	{
		return SignalProducer<PullProgress, DockerError> { observer, _ in
			os_log("starting pull: %{public}@", type:.info, self.imageName)
			self.pullObserver = observer
			do {
				try self.connection.openConnection()
			} catch {
				observer.send(error: DockerError.networkError(error as NSError))
				return
			}
			self.connection.writeRequest()
		}.optionalLog("pull \(imageName)")
	}
	
	private func handle(data: Data)
	{
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

	private func handleStatus(status: String, json: JSON)
	{
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
}
