//
//  MockDockerAPI.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import DockerSupport
import ReactiveSwift
import ClientCore
import Freddy

class MockDockerAPI: DockerAPI {
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
