//
//  DockerAPI.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Freddy
import Foundation
import ReactiveSwift

// MARK: -
/// simple operations that can be performed on a container
public enum DockerContainerOperation: String {
	case start, stop, restart, pause, resume = "unpause"
	public static var all: [DockerContainerOperation] = [.start, .stop, .restart, .pause, .resume]
}

public typealias LogEntryCallback = (_ string: String?, _ isStdErr: Bool) -> Void

public struct DockerVersion: CustomStringConvertible {
	public let major: Int
	public let minor: Int
	public let fix: Int
	public let apiVersion: Double
	
	public var description: String { return "docker \(major).\(minor).\(fix)-\(apiVersion)" }
}

/// Abstracts communicating with docker. Protocol allows for dependency injection.
public protocol DockerAPI: class {
	/// the baseUrl to use for all requests
	var baseUrl: URL { get }
	
	/// Fetches version information from docker daemon
	///
	/// - returns: a signal producer with a single value
	func loadVersion() -> SignalProducer<DockerVersion, DockerError>

	/// initializer
	/// required to allow dynamic call based on class type
	///
	/// - Parameters:
	///   - baseUrl: the base url for the docker server
	///   - sessionConfig: the session configuration to use
	///   - fileManager: the file manager to use for file operations
	init(baseUrl: URL, sessionConfig: URLSessionConfiguration, fileManager: FileManager)
	
	/// Convience method to fetch json
	///
	/// - parameter url: the url that contains json data
	///
	/// - returns: the fetched json data
	func fetchJson(url: URL) -> SignalProducer<JSON, DockerError>

	/// Fetches the logs for the specified container
	///
	/// - Parameter container: the container to get logs for
	/// - Returns: the cotents of the logs (stdout and stderr merged)
	func fetchLog(container: DockerContainer) -> SignalProducer<String, DockerError>
	
	/// Opens a stream to the logs for the specified container
	///
	/// - Parameters:
	///   - container: the container whose logs should be streamed
	///   - dataHandler: closure called when there is log information. If nil is passed, the stream is complete
	///   - string: log content to process
	///   - isStdErr: true if the string is from stderr, false if from stdout
	func streamLog(container: DockerContainer, dataHandler: @escaping LogEntryCallback)

	/// upload a file/directory to a container
	///
	/// - Parameters:
	///   - source: the source url or directory to upload
	///   - path: directory to extract contents into
	///   - filename: the destination file name (possibly source.lastPathComponent)
	///   - containerName: name of container to upload to
	/// - Returns: a signal producer to perform upload operation
	func upload(url source: URL, path: String, filename: String, containerName: String) -> SignalProducer<(), DockerError>

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

	/// Creates a volume on the docker server
	///
	/// - parameter volume: the name of the volume to create
	///
	/// - returns: signal producer that will return no value events
	func create(volume: String) -> SignalProducer<(), DockerError>

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

	/// Execute a command in the specified container asynchronously
	///
	/// - Parameters:
	///   - command: array of command and arguments to perform
	///   - container: the container to use
	/// - Returns: signal producer with the exit code and stdout of the command
	func execute(command: [String], container: DockerContainer) -> SignalProducer<(Int, Data), DockerError>

	/// Executes a command on the docker server synchronously (as vnd.docker.raw-stream) and returns stdout
	///
	/// - Parameters:
	///   - command: the command and arguments to send
	///   - container: the container to execute in
	/// - Returns: the returned data
	func executeSync(command: [String], container: DockerContainer) -> SignalProducer<Data, DockerError>

	/// Executes a command and streams the results returned as Data.
	///
	/// - Parameters:
	///   - command: the command and arguments to send
	///   - container: the container to execute in
	/// - Returns: signal handler that sends each chunk of data received from the command
	func stream(command: [String], container: DockerContainer) -> SignalProducer<Data, DockerError>

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

public extension DockerAPI {
	/// initializes with the default file manager
	/// required to allow dynamic call based on class type
	///
	/// - Parameters:
	///   - baseUrl: the base url for the docker server
	///   - sessionConfig: the session configuration to use
	///   - fileManager: the file manager to use for file operations
	public init(baseUrl: URL, sessionConfig: URLSessionConfiguration, fileManager: FileManager = FileManager.default)
	{
		self.init(baseUrl: baseUrl, sessionConfig: sessionConfig, fileManager: fileManager)
	}
}
