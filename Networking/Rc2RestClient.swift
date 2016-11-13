//
//  Rc2RestClient.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import os
import BrightFutures

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

	public func downloadFile(_ wspace:Workspace, file:File, to destDirUrl:URL) -> Future<URL?, FileError>
	{
		var p = Promise<URL?,FileError>()
		let cacheUrl = URL(fileURLWithPath: file.name, relativeTo: destDirUrl)
		var req = request("workspaces/\(wspace.wspaceId)/files/\(file.fileId)", method: "GET")
		do {
			if try cacheUrl.checkResourceIsReachable() {
				req.addValue("f/\(file.fileId)/\(file.version)", forHTTPHeaderField: "If-None-Match")
			}
		} catch {
		}
		req.addValue(file.fileType.mimeType, forHTTPHeaderField: "Accept")
		let task = urlSession!.downloadTask(with: req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as! HTTPURLResponse
			guard error == nil else { p.failure(.fileNotFound); return }
			switch (hresponse.statusCode) {
			case 304: //use existing
				p.success(cacheUrl)
			case 200: //dloaded it
				self.fileManager.move(tempFile:dloadUrl!, to: cacheUrl, file:file, promise: &p)
			default:
				break
			}
		}
		task.resume()
		return p.future
	}
	
	public func downloadImage(_ wspace:Workspace, imageId:Int, destination:URL) -> Future<URL?,FileError>
	{
		var p = Promise<URL?, FileError>()
		var req = request("workspaces/\(wspace.wspaceId)/images/\(imageId)", method:"GET")
		req.addValue("image/png", forHTTPHeaderField: "Accept")
		let task = urlSession!.downloadTask(with: req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as? HTTPURLResponse
			if error == nil && hresponse?.statusCode == 200 {
				let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: destination)
				self.fileManager.move(tempFile: dloadUrl!, to: fileUrl, file:nil, promise: &p)
			} else {
				p.failure(FileError.failedToSaveFile)
			}
		}
		task.resume()
		return p.future
	}
}
