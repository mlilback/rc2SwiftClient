//
//  DirectoryWatcher.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// object that watches a directory for changes
public final class DirectoryWatcher {
	/// Closure called when the diretory changes
	var changeCallback: (DirectoryWatcher) -> Void

	/// initialize a DirectoryWatcher
	///
	/// - Parameters:
	///   - url: the directory to watch
	///   - callback: closure to call when a change is detected
	public init(url: URL, callback: @escaping (DirectoryWatcher) -> Void) {
		self.url = url
		changeCallback = callback
	}

	private var monitorFileDescriptor: CInt = -1
	private let monitorQueue = DispatchQueue(label: "io.rc2.diretoryWatcher")
	private var monitorSource: DispatchSourceFileSystemObject?
	let url: URL

	/// start watching the directory. has no effect if already started
	public func start() {
		guard monitorSource == nil else { return }

		monitorFileDescriptor = open(url.path, O_EVTONLY)
		monitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: monitorFileDescriptor, eventMask: [.write, .delete], queue: monitorQueue)
		monitorSource?.setEventHandler { [weak self] in
			self?.changeCallback(self!)
		}
		monitorSource?.setCancelHandler { [weak self] in
			guard let me = self else { return }
			close(me.monitorFileDescriptor)
			me.monitorFileDescriptor = -1
			me.monitorSource = nil
		}
		monitorSource?.resume()
	}

	/// stops/removes the directory watcher
	public func stop() {
		monitorSource?.cancel()
		monitorSource = nil
	}
}
