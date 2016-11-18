//
//  ServerSetupController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import ClientCore
import DockerSupport

public class ServerSetupController: NSViewController {
	@IBOutlet fileprivate dynamic var progressBar:NSProgressIndicator?
	@IBOutlet fileprivate dynamic var statusText:NSTextField?
	
	public var pullProgress:PullProgress? { didSet {
		let percent = Double(pullProgress!.currentSize) / Double(pullProgress!.estSize)
		progressBar?.doubleValue = percent
		if pullProgress!.extracting {
			statusText?.stringValue = "Extracting…"
		} else {
			statusText?.stringValue = "Downloading…"
		}
	} }
	
	public var statusMesssage: String {
		get { return statusText?.stringValue ?? "" }
		set { statusText?.stringValue = newValue }
	}
}

