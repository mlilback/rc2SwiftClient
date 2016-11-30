//
//  NSURLRequest+RcDocker.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore

public extension URLRequest {
	public var isChunkedResponse: Bool {
		get { return allHTTPHeaderFields?["Rc2Chunked"] != nil }
		set {
			if nil == allHTTPHeaderFields { allHTTPHeaderFields = [:] }
			allHTTPHeaderFields?["Rc2Chunked"] = newValue ? "true" : nil
		}
	}
}
