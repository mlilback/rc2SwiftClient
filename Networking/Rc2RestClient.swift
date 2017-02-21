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
	
	public init(_ conInfo: ConnectionInfo, fileManager: Rc2FileManager = Rc2DefaultFileManager())
	{
		self.conInfo = conInfo
		self.fileManager = fileManager
		self.sessionConfig = conInfo.urlSessionConfig
		if nil == sessionConfig.httpAdditionalHeaders {
			sessionConfig.httpAdditionalHeaders = [:]
		}
		self.sessionConfig.httpAdditionalHeaders!["Accept"] = "application/json"
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
	
	/// creates a workspace on the server
	///
	/// - Parameters:
	///   - workspace: name of the workspace to create
	///   - project: project to create the workspace in
	/// - Returns: SignalProducer that returns the new workspace or an error
	public func create(workspace: String, project: Project) -> SignalProducer<Workspace, Rc2Error>
	{
		let requestJson: JSON = .dictionary(["projectId": .int(project.projectId), "name": .string(workspace)])
		return SignalProducer<Workspace, Rc2Error> { observer, _ in
			guard let requestData = try? requestJson.serialize() else {
				os_log("failed to encode createworkspace json", log: .session)
				observer.send(error: Rc2Error(type: .network, nested: nil, explanation: "failed to encode json"))
				return
			}
			var req = self.request("workspaces", method: "POST")
			req.addValue("application/json", forHTTPHeaderField: "Content-Type")
			req.addValue("application/json", forHTTPHeaderField: "Accept")
			req.httpBody = requestData
			req.addValue(self.conInfo.authToken, forHTTPHeaderField: "Rc2-Auth")
			let handler = { (data: Data?, response: URLResponse?, error: Error?) in
				self.handleCreateResponse(observer: observer, data: data, response: response, error: error) { newWspace in
					do {
						try project.added(workspace: newWspace)
					} catch {
						os_log("failed to add new workspace to project: %{public}s", log: .session, error.localizedDescription)
						//long-term should refetch the project list
						fatalError()
					}
				}
			}
			self.urlSession!.dataTask(with: req, completionHandler: handler).resume()
		}
	}
	
	/// creates a file on the server
	///
	/// - Parameters:
	///   - fileName: name of the file with extension
	///   - workspace: workspace to contain the file
	///   - contentUrl: optional URL to use as a template for the file
	/// - Returns: SignalProducer for the file to add to the workspace, or an error
	public func create(fileName: String, workspace: Workspace, contentUrl: URL?) -> SignalProducer<File, Rc2Error>
	{
		return SignalProducer<File, Rc2Error> { observer, _ in
			var req = self.request("workspaces/\(workspace.wspaceId)/files/upload", method: "POST")
			req.addValue("0", forHTTPHeaderField: "Content-Length")
			req.addValue("application/octet-string", forHTTPHeaderField: "Content-Encoding")
			req.addValue(fileName, forHTTPHeaderField: "Rc2-Filename")
			req.addValue(self.conInfo.authToken, forHTTPHeaderField: "Rc2-Auth")
			let handler = { (data: Data?, response: URLResponse?, error: Error?) in
				self.handleCreateResponse(observer: observer, data: data, response: response, error: error)
			}
			if let contentUrl = contentUrl {
				self.urlSession!.uploadTask(with: req, fromFile: contentUrl, completionHandler: handler).resume()
			} else {
				self.urlSession!.dataTask(with: req, completionHandler: handler).resume()
			}
		}
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

	private func handleCreateResponse<T: JSONDecodable>(observer: Signal<T, Rc2Error>.Observer, data: Data?, response: URLResponse?, error: Error?, onSuccess: ((T) -> Void)? = nil)
	{
		guard nil == error else { observer.send(error: Rc2Error(type: .cocoa, nested: error)); return }
		switch response?.httpResponse?.statusCode ?? 500 {
		case 201:
			do {
				let json = try JSON(data: data!)
				let object = try T(json: json)
				observer.send(value: object)
				observer.sendCompleted()
				onSuccess?(object)
			} catch {
				observer.send(error: Rc2Error(type: .invalidJson, explanation: "error parsing create REST response"))
			}
		case 422:
			observer.send(error: Rc2Error(type: .invalidArgument, nested: NetworkingError.errorFor(response: response!.httpResponse!, data: data!), explanation: "Workspace already exists with that name"))
		default:
			observer.send(error: Rc2Error(type: .network, nested: NetworkingError.invalidHttpStatusCode(response as! HTTPURLResponse)))
		}
	}
}
