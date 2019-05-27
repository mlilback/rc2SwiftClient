//
//  URLRequest+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension URLRequest {
	/// converts the request to a CFHTTPMessage.
	/// - Warning: does not copy httpBodyStream -- there is no equivilent for CFHTTPMessage
	var CFHTTPMessage: CFHTTPMessage {
		let msg = CFHTTPMessageCreateRequest(kCFAllocatorDefault, httpMethod! as CFString, url! as CFURL, kCFHTTPVersion1_1).takeRetainedValue()
		if let headers = allHTTPHeaderFields {
			for (aKey, aValue) in headers {
				CFHTTPMessageSetHeaderFieldValue(msg, aKey as CFString, aValue as CFString)
			}
		}
		if let body = httpBody {
			CFHTTPMessageSetBody(msg, body as CFData)
		}
		return msg
	}
}

public extension CFHTTPMessage {
	/// the serialized contents of this message
	var serialized: Data? { return CFHTTPMessageCopySerializedMessage(self)?.takeRetainedValue() as Data? }
	/// the serialized contents of this message as a string
	var serializedString: String? {
		guard let data = serialized else { return nil }
		return String(data: data, encoding: .utf8)
	}
}
