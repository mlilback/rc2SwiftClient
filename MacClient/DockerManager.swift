//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

///manages communicating with the local docker engine
public class DockerManager {
	private let socketPath = "/var/run/docker.sock"
	private(set) var primaryVersion:Int = 0
	private(set) var secondaryVersion:Int = 0
	private(set) var fixVersion = 0
	let isInstalled:Bool
	
	init() {
		isInstalled = NSFileManager().fileExistsAtPath(socketPath)
		if isInstalled {
			fetchVersion()
		}
		log.info("docker ver \(primaryVersion).\(secondaryVersion).\(fixVersion)")
	}
	
	private func fetchVersion() {
		do {
			let json = try dockerRequest("version")
			let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
			let verStr = json["Version"].stringValue
			if let match = regex.firstMatchInString(verStr, options: [], range: NSMakeRange(0, verStr.characters.count)) {
				primaryVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(1)))!
				secondaryVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(2)))!
				fixVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(3)))!
			} else {
				log.info("failed to parser version string")
			}
		} catch let err as NSError {
			log.error("error fetchign docker version: \(err)")
		}
	}
	
	///makes a simple GET api request and returns the parsed results
	/// - parameter command: The api command to send. Should not have initial slash.
	func dockerRequest(command:String) throws -> JSON {
		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil)
		}
		var addr = Darwin.sockaddr_un()
		addr.sun_family = UInt8(AF_LOCAL)
		addr.sun_len = UInt8(sizeof(sockaddr_un))
		socketPath.withCString { cpath in
			withUnsafeMutablePointer(&addr.sun_path) { spath in
				strcpy(UnsafeMutablePointer(spath), cpath)
			}
		}
		let code = Darwin.connect(fd, sockaddr_cast(&addr), socklen_t(strideof(sockaddr_un)))
		guard code >= 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil)
		}
		let fh = NSFileHandle(fileDescriptor: fd)
		let outStr = "GET /\(command) HTTP/1.0\r\n\r\n"
		fh.writeData(outStr.dataUsingEncoding(NSUTF8StringEncoding)!)
		let inData = fh.readDataToEndOfFile()
		let responseStr = NSString(data:inData, encoding: NSUTF8StringEncoding)
		let jsonStr = responseStr?.substringFromIndex((responseStr?.rangeOfString("\r\n\r\n").location)! + 4)
		let json = JSON.parse(jsonStr!)
		return json
	}

	private func sockaddr_cast(p: UnsafePointer<sockaddr_un>) -> UnsafePointer<sockaddr> {
		return UnsafePointer<sockaddr>(p)
	}
}
