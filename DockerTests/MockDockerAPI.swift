//
//  MockDockerAPI.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Docker
import ReactiveSwift
import ClientCore
import Freddy

class MockDockerAPI: DockerAPI {
	/// Opens a stream to the logs for the specified container
	///
	/// - Parameters:
	///   - container: the container whose logs should be streamed
	///   - dataHandler: closure called when there is log information. If nil is passed, the stream is complete
	///   - string: log content to process
	///   - isStdErr: true if the string is from stderr, false if from stdout
	func streamLog(container: DockerContainer, dataHandler: @escaping LogEntryCallback) {
		fatalError("not implemented")
	}

	/// Fetches the logs for the specified container
	///
	/// - Parameter container: the container to get logs for
	/// - Returns: the cotents of the logs (stdout and stderr merged)
	func fetchLog(container: DockerContainer) -> SignalProducer<String, Rc2Error> {
		fatalError("not implemented")
	}

	var baseUrl: URL

	func loadVersion() -> SignalProducer<DockerVersion, Rc2Error> {
		fatalError("not implemented")
	}
	
	/// initializer
	required init(baseUrl: URL, sessionConfig: URLSessionConfiguration) {
		fatalError("not implemented")
	}

	func fetchJson(url: URL) -> SignalProducer<JSON, Rc2Error> {
		fatalError("not implemented")
	}

	func execCommand(command: [String], container: DockerContainer) -> SignalProducer<Data, Rc2Error> {
		fatalError("not implemented")
	}

	func loadImages() -> SignalProducer<[DockerImage], Rc2Error> {
		fatalError("not implemented")
	}

	func volumeExists(name: String) -> SignalProducer<Bool, Rc2Error> {
		fatalError("not implemented")
	}

	func create(volume: String) -> SignalProducer<(), Rc2Error> {
		fatalError("not implemented")
	}

	func refreshContainers() -> SignalProducer<[DockerContainer], Rc2Error> {
		fatalError("not implemented")
	}

	func perform(operation: DockerContainerOperation, container: DockerContainer) -> SignalProducer<(), Rc2Error> {
		fatalError("not implemented")
	}

	func perform(operation: DockerContainerOperation, containers: [DockerContainer]) -> SignalProducer<(), Rc2Error> {
		fatalError("not implemented")
	}

	func create(container: DockerContainer) -> SignalProducer<DockerContainer, Rc2Error> {
		fatalError("not implemented")
	}

	func remove(container: DockerContainer) -> SignalProducer<(), Rc2Error> {
		fatalError("not implemented")
	}

	func create(network: String) -> SignalProducer<(), Rc2Error> {
		fatalError("not implemented")
	}

	func networkExists(name: String) -> SignalProducer<Bool, Rc2Error> {
		fatalError("not implemented")
	}


}
