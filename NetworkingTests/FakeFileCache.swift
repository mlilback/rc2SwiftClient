//
//  FakeFileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Result
import ClientCore
import ReactiveSwift
@testable import Networking

///used by the FakeFileCache to know how to respond to a request
struct FakeFileInfo {
	var fileId: Int
	var data: Data?
	var url: URL?
	var cached: Bool = false
}

class FakeFileCache: FileCache {
	func close() {
	}
	
	let baseUrl: URL
	var fileManager: Rc2FileManager
	var workspace: Workspace
	var fileInfo: [Int: FakeFileInfo] = [:]
	
	init(workspace: Workspace, baseUrl: URL) {
		self.baseUrl = baseUrl
		fileManager = Rc2DefaultFileManager()
		self.workspace = workspace
	}
	
	func isFileCached(_ file:File) -> Bool {
		guard let iscached = fileInfo[file.fileId]?.cached else { return false }
		return iscached
	}
	
	//removes the cached file
	func flushCache(file: File) {
		guard var finfo = fileInfo[file.fileId] else { return }
		finfo.cached = false
	}
	
	func recache(file: File) -> SignalProducer<Double, Rc2Error> {
		if nil != fileInfo[file.fileId] {
			fileInfo[file.fileId]!.cached = true
			return SignalProducer<Double, Rc2Error>(value: 1.0)
		}
		let finfo = FakeFileInfo(fileId: file.fileId, data: nil, url: nil, cached: true)
		fileInfo[file.fileId] = finfo
		return SignalProducer<Double, Rc2Error>(value: 1.0)
	}
	
	func flushCache(files: [File]) -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error> { observer, _ in
			for aFile in files {
				if self.fileInfo[aFile.fileId] != nil {
					self.fileInfo[aFile.fileId]!.cached = false
				}
			}
			observer.send(value: 1.0)
			observer.sendCompleted()
		}
	}
	
	func cacheAllFiles() -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error>(value: 1.0)
	}
	
	func cachedUrl(file: File) -> URL {
		if let furl = fileInfo[file.fileId]?.url {
			return furl
		}
		return URL(string: "workspaces/\(workspace.wspaceId)/files/\(file.fileId)", relativeTo: baseUrl)!
	}
	
	func validUrl(for file: File) -> SignalProducer<URL, Rc2Error> {
		return SignalProducer<URL, Rc2Error>(error: Rc2Error(type: .unknown, explanation: "not implemented"))
	}
	
	func contents(of file: File) -> SignalProducer<Data, Rc2Error> {
		guard let finfo = fileInfo[file.fileId] else {
			return SignalProducer<Data, Rc2Error>(error: Rc2Error(type: .noSuchElement))
		}
		if let data = finfo.data {
			return SignalProducer<Data, Rc2Error>(value: data)
		}
		guard let furl = finfo.url else {
			return SignalProducer<Data, Rc2Error>(error: Rc2Error(type: .noSuchElement))
		}
		do {
			let fdata = try Data(contentsOf: furl)
			return SignalProducer<Data, Rc2Error>(value: fdata)
		} catch {
			return SignalProducer<Data, Rc2Error>(error: Rc2Error(type: .file, nested: error, explanation: "no data for file"))
		}
	}
	
	func update(file: File, withData data: Data?) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error>(error: Rc2Error(type: .unknown, explanation: "not implemented"))
	}
	
	func save(file: File, contents: String) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error>(error: Rc2Error(type: .unknown, explanation: "not implemented"))
	}
}
