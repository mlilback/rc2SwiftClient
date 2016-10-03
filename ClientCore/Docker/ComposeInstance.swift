//
//  ComposeInstance.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import os

class ComposeInstance {
	let homeDirectory:URL
	fileprivate(set) var running:Bool = false
	fileprivate(set) var task:Process
	fileprivate var stdoutSrc: DispatchSourceRead?
	fileprivate var stderrSrc: DispatchSourceRead?
	
	init(at:URL) {
		homeDirectory = at
		task = Process()
		task.currentDirectoryPath = homeDirectory.path
		task.launchPath = "/usr/local/bin/docker-compose"
		task.arguments = ["up"]
		task.terminationHandler = { p in
			self.taskExited(p)
		}
	}
	
	deinit {
		if task.isRunning {
			stderrSrc?.cancel()
			stdoutSrc?.cancel()
			task.terminate()
		}
	}
	
	func start() -> Future<Bool, NSError> {
		let stdout = Pipe()
		let stderr = Pipe()
		task.standardError = stderr
		task.standardOutput = stdout
		let promise = Promise<Bool,NSError>()
		stdoutSrc = DispatchSource.makeReadSource(fileDescriptor: stdout.fileHandleForReading.fileDescriptor, queue: DispatchQueue.global(qos: .default))
		stderrSrc = DispatchSource.makeReadSource(fileDescriptor: stderr.fileHandleForReading.fileDescriptor, queue: DispatchQueue.global(qos: .default))
		stdoutSrc?.setEventHandler {
			self.parseStdOut()
		}
		stderrSrc?.setEventHandler {
			self.parseStdErr()
		}
		task.launch()
		running = true
		return promise.future
	}
	
	func parseStdOut() {
		
	}
	
	func parseStdErr() {
	
	}
	
	func taskExited(_ process:Process) {
		running = false
		stdoutSrc?.cancel()
		stdoutSrc = nil
		stderrSrc?.cancel()
		stderrSrc = nil
	}
}
