//
//  NSURLRequest+RcDocker.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore

public extension URLRequest {
	public var isHijackedResponse: Bool {
		get { return allHTTPHeaderFields?["Rc2Hijacked"] != nil }
		set {
			if nil == allHTTPHeaderFields { allHTTPHeaderFields = [:] }
			allHTTPHeaderFields?["Rc2Hijacked"] = newValue ? "true" : nil
		}
	}
}
