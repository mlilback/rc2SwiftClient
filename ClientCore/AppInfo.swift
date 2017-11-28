//
//  AppInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// a static reference to the app's bundle
public struct AppInfo {
	/// the info dictionary of the application
	private static let bundleInfo = Bundle.main.infoDictionary
	/// the bundle identifier of the application
	public static var bundleIdentifier: String { return bundleInfo?["CFBundleIdentifier"] as? String ?? "io.rc2.MacClient" }
	/// application build number (for error reports/about box)
	public static var buildNumber: String { return bundleInfo?["CFBundleVersion"] as? String ?? "??" }

	/// Returns the URL to a subdirectory of app's application support directory (created if doesn't already exist)
	///
	/// - Parameter name: the name of the subdirectory
	/// - Returns: the url to that directory
	/// - Throws: any error thrown by FileManager calls
	public static func subdirectory(type: FileManager.SearchPathDirectory, named: String) throws -> URL {
		let fm = FileManager()
		let rootDir = try fm.url(for: type, in: .userDomainMask, appropriateFor: nil, create: false)
		let subdir = rootDir.appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true).appendingPathComponent(named, isDirectory: true)
		if !fm.directoryExists(at: subdir) {
			try fm.createDirectory(at: subdir, withIntermediateDirectories: true, attributes: nil)
		}
		return subdir
	}
	
	/// Checks if the app is running in a debugger
	public static var amIBeingDebugged: Bool = {
		var info = kinfo_proc()
		var mib : [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
		var size = MemoryLayout<kinfo_proc>.stride
		let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
		assert(junk == 0, "sysctl failed")
		return (info.kp_proc.p_flag & P_TRACED) != 0
	}()
}
