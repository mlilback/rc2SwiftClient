//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class DockerManager {
	let binaryPath: String
	private(set) var composeVersion:Double = 0
	private(set) var composeBuild:String = ""
	let isInstalled:Bool
	
	///allow dependency injection of docker binary to use
	init(binaryPath:String = "/usr/local/bin/docker-compose") {
		self.binaryPath = binaryPath
		isInstalled = NSFileManager().fileExistsAtPath(binaryPath)
		if isInstalled {
			fetchComposeVersion()
		}
	}
	
	var isComposeUsable: Bool { return composeVersion >= 1.8 && composeVersion < 2.0 }
	
	func fetchComposeVersion() {
		do {
			let versionStrs = try ShellCommands.stdout(for: binaryPath, arguments:["-v"], pattern:"version (.*), build (.*)")
			if versionStrs.count == 3
			{
				composeVersion = (versionStrs[1] as NSString).doubleValue
			}
		} catch let err {
			print("got error \(err)")
		}
	}
}
