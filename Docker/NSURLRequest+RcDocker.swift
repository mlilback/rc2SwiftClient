//
//  NSURLRequest+RcDocker.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension URLRequest {
	public var isHijackedResponse: Bool {
		get { return allHTTPHeaderFields?["Rc2Hijacked"] != nil }
		set {
			if nil == allHTTPHeaderFields { allHTTPHeaderFields = [:] }
			allHTTPHeaderFields?["Rc2Hijacked"] = newValue ? "true" : nil
		}
	}
	public var asCFHTTPMessage: CFHTTPMessage {
		precondition(httpBodyStream == nil, "body streams unsupported")
		let msg = CFHTTPMessageCreateRequest(kCFAllocatorDefault, httpMethod! as CFString, url! as CFURL, kCFHTTPVersion1_1).takeRetainedValue()
		if let headers = allHTTPHeaderFields {
			for (aKey, aValue) in headers {
				CFHTTPMessageSetHeaderFieldValue(msg, aKey as CFString, aValue as CFString)
			}
		}
		CFHTTPMessageSetHeaderFieldValue(msg, "Connection" as CFString, "closed" as CFString)
		if let body = httpBody {
			CFHTTPMessageSetBody(msg, body as CFData)
		}
		return msg
	}
}
