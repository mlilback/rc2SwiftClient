//
//  Rc2RestClient.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import ClientCore
import os

public final class Rc2RestClient {
	let conInfo: ConnectionInfo
	let sessionConfig: URLSessionConfiguration
	fileprivate var urlSession: URLSession?
	fileprivate var networkLog: OSLog! // we will create before init is complete
	let fileManager: Rc2FileManager
	
	public init(_ conInfo: ConnectionInfo, sessionConfig: URLSessionConfiguration = .default, fileManager: Rc2FileManager = Rc2DefaultFileManager())
	{
		self.conInfo = conInfo
		self.fileManager = fileManager
		self.sessionConfig = sessionConfig
		self.sessionConfig.httpAdditionalHeaders = ["Accept": "application/json", "Rc2-Auth": conInfo.authToken]
		urlSession = URLSession(configuration: sessionConfig)
		networkLog = OSLog(subsystem: Bundle().bundleIdentifier ?? "io.rc2.client", category: "networking")
	}
	
	fileprivate func request(_ path:String, method:String) -> URLRequest
	{
		let url = URL(string: path, relativeTo: conInfo.host.url!)
		var request = URLRequest(url: url!)
		request.httpMethod = method
		return request
	}
	
	public func downloadImage(imageId: Int, from wspace: Workspace, destination:URL) -> SignalProducer<URL, Rc2Error>
	{
		return SignalProducer<URL, Rc2Error>() { observer, _ in
			var req = self.request("workspaces/\(wspace.wspaceId)/images/\(imageId)", method:"GET")
			req.addValue("image/png", forHTTPHeaderField: "Accept")
			let task = self.urlSession!.downloadTask(with: req) { (dloadUrl, response, error) -> Void in
				let hresponse = response as? HTTPURLResponse
				guard error == nil && hresponse?.statusCode == 200 else {
					let err = Rc2Error(type: .file, nested: FileError.failedToSave)
					observer.send(error: err)
					return
				}
				let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: destination)
				do {
					try self.fileManager.move(tempFile: dloadUrl!, to: fileUrl, file:nil)
				} catch {
					observer.send(error: Rc2Error(type: .file, nested: FileError.failedToDownload, severity: .warning, explanation: "image \(imageId)"))
				}
			}
			task.resume()
		}
	}
}
