//
//  NetworkingBaseSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Rc2Common
import Networking

class NetworkingBaseSpec: QuickSpec {
	/// Load Data from a resource file
	///
	/// - Parameter fileName: name of the resource to load w/o file extension
	/// - Parameter fileExtension: the file extension of the resource to load
	/// - Returns: the Data object with the contents of the file
	func loadFileData(_ fileName: String, fileExtension: String) -> Data? {
		let bundle = Bundle(for: type(of: self))
		guard let url = bundle.url(forResource: fileName, withExtension: fileExtension),
			let data = try? Data(contentsOf: url)
		else
		{
			fatalError("failed to load \(fileName).\(fileExtension)")
		}
		return data
	}

	/// Load and parse a json file
	///
	/// - Parameter fileName: name of the file without the ".json"
	/// - Returns: the parsed json
//	func loadTestJson(_ fileName: String) -> JSON {
//		let bundle = Bundle(for: type(of: self))
//		guard let url = bundle.url(forResource: fileName, withExtension: "json"),
//			let data = try? Data(contentsOf: url),
//			let json = try? JSON(data: data)
//		else
//		{
//			fatalError("failed to load \(fileName).json")
//		}
//		return json
//	}

	/// Returns a ConnectionInfo object created with bulkInfo.json
	///
	/// - Returns: ConnectionInfo for use
	func genericConnectionInfo() -> ConnectionInfo {
		let bulkData = self.loadFileData("bulkInfo", fileExtension: "json")!
		return try! ConnectionInfo(host: ServerHost.localHost, bulkInfoData: bulkData, authToken: "dsfrsfsdfsdfsf")
	}

	/// Executes a producer returning the last value
	///
	/// - Parameters:
	///   - producer: the producer to execute
	///   - queue: the queue to execute on, defaults to .global()
	/// - Returns: a result with the last value
	func makeValueRequest<T>(producer: SignalProducer<T, Rc2Error>, queue: DispatchQueue = .global()) -> Result<T, Rc2Error>
	{
		var result: Result<T, Rc2Error>!
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.last()
		}
		group.wait()
		return result
	}
	
	/// Starts the producer and blocks until completed or an error happens
	///
	/// - Parameters:
	///   - producer: the producer to start
	///   - queue: the queue to perform on, defaults to global queue
	/// - Returns: a result with true if completed, error if failed
	func makeCompletedRequest<T>(producer: SignalProducer<T, Rc2Error>, queue: DispatchQueue = .global()) -> Result<Bool, Rc2Error>
	{
		var result = Result<Bool, Rc2Error>(catching: { true })
		let group = DispatchGroup()
		group.enter()
		queue.async(group: group) {
			producer.start { event in
				switch event {
				case .failed(let err):
					result = Result<Bool, Rc2Error>(error: err)
					group.leave()
				case .value(_):
					break
				case .completed:
					result = Result<Bool, Rc2Error>(true)
					fallthrough
				case .interrupted:
					group.leave()
				}
			}
		}
		let success = group.wait(timeout: .now() + .seconds(90))
		if case .timedOut = success {
			result = Result<Bool, Rc2Error>(error: Rc2Error(type: .unknown, explanation: "timed out"))
		}
		return result
	}
}
