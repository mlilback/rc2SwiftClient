//
//  DockerAPI.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift

//MARK: -
/// simple operations that can be performed on a container
public enum DockerContainerOperation: String {
	case start, stop, restart, pause, resume = "unpause"
}

/// Abstracts communicating with docker. Protocol allows for dependency injection.
protocol DockerAPI {
	/// Fetches the current containers from the docker daemon
	///
	/// - returns: a signal producer that will send a single value and a completed event, or an error event
	func refreshContainers() -> SignalProducer<[DockerContainer], NSError>

	/// Performs an operation on a docker container
	///
	/// - parameter operation: the operation to perform
	/// - parameter container: the target container
	///
	/// - returns: a signal producer that will return no Next events
	func perform(operation: DockerContainerOperation, on container: DockerContainer) -> SignalProducer<(), NSError>
}
