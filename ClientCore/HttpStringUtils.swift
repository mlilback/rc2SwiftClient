//
//  HttpStringUtils.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class HttpStringUtils {
	public enum UtilError: Error {
		case invalidInput
	}

	///splits raw data into headers and content
	///
	/// - parameter data: raw data to split
	/// - returns: a tuple of the header and content strings
	public class func splitResponseData(_ data: Data) throws -> (Data, Data) {
		guard data.count > 5 else { throw UtilError.invalidInput }
		let splitRange = data.range(of: Data(bytes: [UInt8(13), UInt8(10), UInt8(13), UInt8(10)]))
		guard splitRange != nil else { throw UtilError.invalidInput }
		let headerData = data.subdata(in: data.startIndex..<splitRange!.lowerBound)
		let contentData = data.subdata(in: splitRange!.upperBound..<data.endIndex)
		return (headerData, contentData)
	}

	///extracts headers into a dictionary
	/// - parameter headerString: the raw headers from an HTTP response
	/// - returns: tuple of the HTTP status code, HTTP version, and a dictionary of headers
	public class func extractHeaders(_ responseString: String) throws -> (status: Int, version: String, headers: [String:String])
	{
		// swiftlint:disable:next force_try
		let responseRegex = try! NSRegularExpression(pattern: "^(HTTP/1.\\d) (\\d+)( .*?\r\n)(.*)", options: [.anchorsMatchLines, .dotMatchesLineSeparators])
		guard let matchResult = responseRegex.firstMatch(in: responseString, options: [], range: responseString.fullNSRange), matchResult.numberOfRanges == 5,
			let statusString = responseString.substring(from: matchResult.rangeAt(2)),
			let statusCode = Int(statusString),
			let versionString = responseString.substring(from: matchResult.rangeAt(1)),
			let headersString = responseString.substring(from: matchResult.rangeAt(4))
			else { throw UtilError.invalidInput }
		var headers = [String:String]()
		// swiftlint:disable:next force_try
		let headerRegex = try! NSRegularExpression(pattern: "(.+): (.*)", options: [])
		headerRegex.enumerateMatches(in: headersString, options: [], range: headersString.fullNSRange)
		{ (matchResult, _, _) in
			if let match = matchResult,
				let key = headersString.substring(from: match.rangeAt(1)),
				let value = headersString.substring(from: match.rangeAt(2))
			{
				headers[key] = value
			}
		}
		return (statusCode, versionString, headers)
	}
}
