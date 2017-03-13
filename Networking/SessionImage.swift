//
//  SessionImage.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os

public struct SessionImage: JSONDecodable, JSONEncodable, Equatable {
	public let id: Int
	public let batchId: Int
	public let name: String!
	public let imageData: Data?
	public let dateCreated: Date!
	
	fileprivate static var dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "YYYY-MM-dd"
		return formatter
	}()
	
	/// initializer for JSONDecodable. Just calls through to init(json, batchId)
	///
	/// - Parameter json: JSON object
	/// - Throws: json decoding errors
	public init(json: JSON) throws {
		try self.init(json: json, batchId: 0)
	}
	
	/// default initializer
	///
	/// - Parameters:
	///   - json: source JSON
	///   - batchId: batchId, defaulting to zero
	/// - Throws: json decoding error
	public init(json: JSON, batchId: Int = 0) throws {
		do {
			self.id = try json.getInt(at: "id")
			self.batchId = batchId == 0 ? try json.getInt(at: "batchId") : batchId
			self.name = try json.getString(at: "name")
			self.dateCreated = SessionImage.dateFormatter.date(from: try json.getString(at: "dateCreated"))
			var imgData: Data? = nil
			if let dataStr = try? json.getString(at: "imageData") {
				imgData = Data(base64Encoded: dataStr)
			}
			self.imageData = imgData
		} catch {
			os_log("error decoding SessionImage from json: %{public}@", log: .session, error.localizedDescription)
			throw error
		}
	}
	
	/// creates a copy of original without the image data
	///
	/// - Parameter original: the image to copy w/o imageData
	public init(_ original: SessionImage) {
		id = original.id
		batchId = original.batchId
		name = original.name
		dateCreated = original.dateCreated
		imageData = nil
	}
	
	public func toJSON() -> JSON {
		return .dictionary(["id": .int(id), "batchId": .int(batchId), "name": .string(name), "dateCreated": .string(SessionImage.dateFormatter.string(from: dateCreated))])
	}
	
	public static func == (lhs: SessionImage, rhs: SessionImage) -> Bool {
		return lhs.id == rhs.id && lhs.batchId == rhs.batchId && lhs.name == rhs.name && lhs.dateCreated == rhs.dateCreated
	}
}
