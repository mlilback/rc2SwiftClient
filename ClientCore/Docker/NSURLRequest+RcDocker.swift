//
//  NSURLRequest+RcDocker.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension URLRequest {
	public var isChunkedResponse: Bool {
		get { return (self as NSURLRequest).rc2_chunkedResponse }
		set { (self as NSURLRequest).rc2_chunkedResponse = newValue }
	}
}
