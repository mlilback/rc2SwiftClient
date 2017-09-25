//
//  Rc2RestClient.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import Freddy
import os
import ReactiveSwift
import ZipArchive
import Model

fileprivate let wspaceDirName = "defaultWorkspaceFiles"

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
	
	fileprivate func request(_ path: String, method: String) -> URLRequest
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
	public func create(workspace: String, project: AppProject) -> SignalProducer<AppWorkspace, Rc2Error>
	{
		return SignalProducer<AppWorkspace, Rc2Error> { observer, _ in
			var req = self.request("proj/\(project.projectId)/wspace", method: "POST")
			let zippedUrl = self.defaultWorkspaceFiles()
			if zippedUrl != nil, let zippedData = try? Data(contentsOf: zippedUrl!) {
				req.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
				req.addValue(workspace, forHTTPHeaderField: "Rc2-WorkspaceName")
				req.httpBody = zippedData
			} else {
				req.addValue("application/json", forHTTPHeaderField: "Content-Type")
			}
			req.addValue("application/json", forHTTPHeaderField: "Accept")
			let handler = { (data: Data?, response: URLResponse?, error: Error?) in
				do {
					let results: CreateWorkspaceResult = try self.handleResponse(data: data, response: response, error: error)
					self.conInfo.update(bulkInfo: results.bulkInfo)
					let wspace = try self.conInfo.workspace(withId: results.wspaceId, in: project)
					observer.send(value: wspace)
					observer.sendCompleted()
				} catch let nferror as ConnectionInfo.Errors {
					os_log("created workspace not found", log: .network)
					observer.send(error: Rc2Error(type: .network, nested: nferror, explanation: "created workspace not found"))
				} catch let rc2error as Rc2Error {
					observer.send(error: rc2error)
				} catch {
					os_log("error parsing create workspace response %{public}@", log: .network, error.localizedDescription)
					observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "unknown error parsing create workspace response"))
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
	public func create(fileName: String, workspace: AppWorkspace, contentUrl: URL?) -> SignalProducer<File, Rc2Error>
	{
		return SignalProducer<File, Rc2Error> { observer, _ in
			var req = self.request("workspaces/\(workspace.wspaceId)/files/upload", method: "POST")
			req.addValue("0", forHTTPHeaderField: "Content-Length")
			req.addValue("application/octet-string", forHTTPHeaderField: "Content-Encoding")
			req.addValue(fileName, forHTTPHeaderField: "Rc2-Filename")
			req.addValue(self.conInfo.authToken, forHTTPHeaderField: "Rc2-Auth")
			let handler = { (data: Data?, response: URLResponse?, error: Error?) in
				do {
					let file: File = try self.handleResponse(data: data, response: response, error: error)
					observer.send(value: file)
					observer.sendCompleted()
				} catch let err as Rc2Error {
					observer.send(error: err)
				} catch {
				os_log("error parsing create workspace response %{public}@", log: .network, error.localizedDescription)
				observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "unknown error parsing create workspace response"))
				}
			}
			if let contentUrl = contentUrl {
				self.urlSession!.uploadTask(with: req, fromFile: contentUrl, completionHandler: handler).resume()
			} else {
				self.urlSession!.dataTask(with: req, completionHandler: handler).resume()
			}
		}
	}
	
	public func downloadImage(imageId: Int, from wspace: AppWorkspace, destination: URL) -> SignalProducer<URL, Rc2Error>
	{
		return SignalProducer<URL, Rc2Error> { observer, _ in
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
	
	/// returns array of default files to add to any new workspace
	/// - returns: URL to a zip file with the default files to add
	private func defaultWorkspaceFiles() -> URL? {
		let fm = FileManager()
		do {
			let defaultDirectoryUrl = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: wspaceDirName)
			if try fm.contentsOfDirectory(atPath: defaultDirectoryUrl.path).isEmpty {
				//copy all template files to user-editable directory
				let templateDir = (Bundle(for: type(of: self)).resourceURL?.appendingPathComponent(wspaceDirName, isDirectory: true))!
				for aUrl in try fm.contentsOfDirectory(at: templateDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
				{
					try fm.copyItem(at: aUrl, to: defaultDirectoryUrl.appendingPathComponent(aUrl.lastPathComponent))
				}
			}
			let destUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).zip")
			guard SSZipArchive.createZipFile(atPath: destUrl.path, withContentsOfDirectory: defaultDirectoryUrl.path, keepParentDirectory: false) else
			{
				os_log("failed to create zip file to upload", log: .network)
				return nil
			}
			return destUrl
		} catch {
			os_log("error loading default workspace files: %{public}@", log: .network, error as NSError)
		}
		return nil
	}
	
	/// parses the response from a URLSessionTask callback
	///
	/// - Parameters:
	///   - data: data parameter from callback
	///   - response: response parameter from callback
	///   - error: error parameter from callback
	/// - Returns: decoded object from data
	/// - Throws: server error wrapped as Rc2Error
	private func handleResponse<T: Decodable>(data: Data?, response: URLResponse?, error: Error?) throws -> T
	{
		guard nil == error else { throw Rc2Error(type: .cocoa, nested: error) }
		switch response?.httpResponse?.statusCode ?? 500 {
		case 201:
			do {
				let object: T = try conInfo.decode(data: data!)
				return object
			} catch {
				throw Rc2Error(type: .invalidJson, explanation: "error parsing create REST response")
			}
		case 422:
			throw Rc2Error(type: .invalidArgument, nested: NetworkingError.errorFor(response: response!.httpResponse!, data: data!), explanation: "Workspace already exists with that name")
		default:
			// swiftlint:disable:next force_cast
			throw Rc2Error(type: .network, nested: NetworkingError.invalidHttpStatusCode(response as! HTTPURLResponse))
		}
	}
}
