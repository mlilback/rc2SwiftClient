//
//  ServerSetupController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import ClientCore

public class ServerSetupController: NSViewController {
	@IBOutlet dynamic var progressBar:NSProgressIndicator?
	@IBOutlet dynamic var statusText:NSTextField?
	public var pullProgress:PullProgress? { didSet {
		let percent = Double(pullProgress!.currentSize) / Double(pullProgress!.estSize)
		progressBar?.doubleValue = percent
		if pullProgress!.extracting {
			statusText?.stringValue = "Extracting…"
		} else {
			statusText?.stringValue = "Downloading…"
		}
	} }
	
}

