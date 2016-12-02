//
//  BaseDockerSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Result
import Mockingjay
import ClientCore
@testable import DockerSupport

/// a subclass of QuickSpec that has utility methods useful for docker testing
class BaseDockerSpec: QuickSpec {
	override func spec() {
		describe("") {
			
		}
	}

	/// Loads the data from the resource file (in the tests bundle)
	///
	/// - Parameters:
	///   - fileName: name of resource
	///   - fileExtension: file extension of resource
	/// - Returns: contents of fileName.fileExtension
	func resourceDataFor(fileName: String, fileExtension: String) -> Data {
		let path = Bundle(for: type(of: self)).path(forResource: fileName, ofType: fileExtension)
		let data = try! Data(contentsOf: URL(fileURLWithPath: path!))
		return data
	}

	/// Completes a signal producer returning the results
	///
	/// - Parameters:
	///   - producer: The producer to run
	///   - queue: the queue to run it on (should not be main queue in a unit test)
	/// - Returns: the result of the producer
	func makeValueRequest<T>(producer: SignalProducer<T, Rc2Error>, queue: DispatchQueue) -> Result<T, Rc2Error> {
		var result: Result<T, Rc2Error>!
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.single()
		}
		group.wait()
		return result
	}
	
	/// Completes a signal producer that has no value
	///
	/// - Parameters:
	///   - producer: The producer to run
	///   - queue: the queue to run it on (should not be main queue in a unit test)
	/// - Returns: the result of the producer
	func makeNoValueRequest(producer: SignalProducer<(), Rc2Error>, queue: DispatchQueue) -> Result<(), Rc2Error> {
		var result: Result<(), Rc2Error>?
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.wait()
		}
		group.wait()
		return result!
	}
	
	/// Performs a refreshContainers returning the results
	///
	/// - Parameters:
	///   - api: the api object to call refreshContainers on
	///   - queue: the queue to perform the operation on
	/// - Returns: the result of the call
	func loadContainers(api: DockerAPI, queue:DispatchQueue) -> Result<[DockerContainer], Rc2Error> {
		let scheduler = QueueScheduler(name: "\(#file)\(#line)")
		let producer = api.refreshContainers().observe(on: scheduler)
		var result: Result<[DockerContainer], Rc2Error>?
		let group = DispatchGroup()
		
		queue.async(group: group) {
			result = producer.single()
		}
		group.wait()
		guard let r = result else {
			fatalError("failed to get result from refreshContainers()")
		}
		return r
	}
	
	/// returns a custom matcher looking for a post request at the specified path
	func postMatcher(uriPath: String) -> (URLRequest) -> Bool {
		return { request in
			return request.httpMethod == "POST" && request.url!.path.hasPrefix(uriPath)
		}
	}
	
	/// uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath: String, fileName: String) {
		let path : String = Bundle(for: type(of:self)).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(uri(uri: uriPath), builder: jsonData(resultData!))
	}
}
