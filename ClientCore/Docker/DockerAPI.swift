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
	public static var all: [DockerContainerOperation] = [.start, .stop, .restart, .pause, .resume]
}

/// Abstracts communicating with docker. Protocol allows for dependency injection.
protocol DockerAPI {
	/// Fetches the current containers from the docker daemon
	///
	/// - returns: a signal producer that will send a single value and a completed event, or an error event
	func refreshContainers() -> SignalProducer<[DockerContainer], DockerError>

	/// Performs an operation on a docker container
	///
	/// - parameter operation: the operation to perform
	/// - parameter container: the target container
	///
	/// - returns: a signal producer that will return no value events
	func perform(operation: DockerContainerOperation, container: DockerContainer) -> SignalProducer<(), DockerError>

	/// Performs an operation on multiple containers
	///
	/// - parameter operation: the operation to perform
	/// - parameter on:        array of containers to perform the operation on
	///
	/// - returns: a signal responder with no value events
	func perform(operation: DockerContainerOperation, containers: [DockerContainer]) -> SignalProducer<(), DockerError>
}
