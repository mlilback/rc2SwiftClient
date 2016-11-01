//
//  DockerAPI.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import SwiftyJSON

//MARK: -
/// simple operations that can be performed on a container
public enum DockerContainerOperation: String {
	case start, stop, restart, pause, resume = "unpause"
	public static var all: [DockerContainerOperation] = [.start, .stop, .restart, .pause, .resume]
}

public struct DockerVersion {
	public let major: Int
	public let minor: Int
	public let fix: Int
	public let apiVersion: Double
}

/// Abstracts communicating with docker. Protocol allows for dependency injection.
public protocol DockerAPI {
	var baseUrl: URL { get }
	/// Fetches version information from docker daemon
	///
	/// - returns: a signal producer with a single value
	func loadVersion() -> SignalProducer<DockerVersion, DockerError>

	/// Convience mehtod to fetch json
	///
	/// - parameter url: the url that contains json data
	///
	/// - returns: the fetched json data
	func fetchJson(url: URL) -> SignalProducer<JSON, DockerError>

	/// Loads images from docker daemon
	///
	/// - returns: signal producer that will send array of images
	func loadImages() -> SignalProducer<[DockerImage], DockerError>

	/// checks to see if the named volume exists
	///
	/// - parameter name: the name to look for
	///
	/// - returns: true if a network exists with that name
	func volumeExists(name: String) -> SignalProducer<Bool, DockerError>

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
	/// - returns: a signal producer with no value events
	func perform(operation: DockerContainerOperation, containers: [DockerContainer]) -> SignalProducer<(), DockerError>

	/// Create a container on the docker server if it doesn't exsist
	///
	/// - parameter container: the container to create on the server
	///
	/// - returns: the parameter unchanged
	func create(container: DockerContainer) -> SignalProducer<DockerContainer, DockerError>

	/// Remove a container
	///
	/// - parameter container: container to remove
	///
	/// - returns: a signal procuder with no value events
	func remove(container: DockerContainer) -> SignalProducer<(), DockerError>

	/// create a netork
	///
	/// - parameter network: name of network to create
	///
	/// - returns: a signal producer that will return no values
	func create(network: String) -> SignalProducer<(), DockerError>

	/// check to see if a netwwork exists
	///
	/// - parameter name: name of network
	///
	/// - returns: a signal producer with a single Bool value
	func networkExists(name: String) -> SignalProducer<Bool, DockerError>
}
