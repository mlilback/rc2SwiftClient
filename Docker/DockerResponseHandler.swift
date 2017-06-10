//
//  DockerResponseHandler.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os

protocol DockerResponseHandler: class {
	init(channel: DispatchIO, queue: DispatchQueue, handler: @escaping DockerMessageHandler)
	var callback: DockerMessageHandler { get }
	var headers: HttpHeaders? { get set }
	func startHandler()
	func closeHandler()
}

extension DockerResponseHandler {
	func parseHeaders(data: Data) throws -> Data {
		do {
			let (headData, remainingData) = try HttpStringUtils.splitResponseData(data)
			guard let headString = String(data: headData, encoding: .utf8),
				let parsedHeaders = try? HttpStringUtils.extractHeaders(headString)
				else
			{
				os_log("failed to parse headers", log: .docker)
				throw DockerError.internalError("failed to parse headers")
			}
			guard parsedHeaders.statusCode >= 200, parsedHeaders.statusCode <= 299 else {
				throw DockerError.httpError(statusCode: parsedHeaders.statusCode, description: nil, mimeType: nil)
			}
			headers = parsedHeaders
			return remainingData
		} catch {
			os_log("error parsing data %{public}@", log: .docker, error as NSError)
			throw error
		}
	}
}
