//
//  UserDefaults+JSON.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import SwiftyUserDefaults
import MJLLogger

public final class DefaultsJSONBridge: DefaultsBridge<JSON> {
	override public func get(key: String, userDefaults: UserDefaults) -> JSON? {
		guard let data = userDefaults.data(forKey: key), let json = try? JSON(data: data)
			else { return nil }
		return json
	}
	override public func save(key: String, value: JSON?, userDefaults: UserDefaults) {
		do {
			guard let object = value else {
				userDefaults.set(nil, forKey: key)
				return
			}
			userDefaults.set(try object.serialize(), forKey: key)
		} catch {
			Log.warn("error saving JSON to defaults: \(error)", .core)
		}
	}
	public override func isSerialized() -> Bool { return true }
	
	public override func deserialize(_ object: Any) -> JSON? {
		guard let data = object as? Data, let json = try? JSON(data: data)
		else { return nil }
		return json
	}
}

public final class DefaultsJSONArrayBridge: DefaultsBridge<[JSON]> {
	override public func get(key: String, userDefaults: UserDefaults) -> [JSON]? {
		return userDefaults.array(forKey: key)?
			.compactMap { $0 as? JSON }
	}

	override public func save(key: String, value: [JSON]?, userDefaults: UserDefaults) {
		guard let object = value else {
			userDefaults.set(nil, forKey: key)
			return
		}
		let array = object
			.compactMap { try? $0.serialize() }
		userDefaults.set(array, forKey: key)
	}
	public override func isSerialized() -> Bool { return true }

	public override func deserialize(_ object: Any) -> [JSON]? {
		guard let data = object as? [Data]
			else { return nil }
		return data.compactMap { try? JSON(data: $0) }
	}
}

extension JSON: DefaultsSerializable {
	public static var _defaults: DefaultsBridge<JSON> { return DefaultsJSONBridge() }
	public static var _defaultsArray: DefaultsBridge<[JSON]> { return DefaultsJSONArrayBridge() }
}

extension FontDescriptor: DefaultsSerializable {
}

extension CGFloat: DefaultsSerializable {
	public static var _defaults: DefaultsBridge<Double> { return DefaultsDoubleBridge() }
	public static var _defaultsArray: DefaultsBridge<[Double]> { return DefaultsArrayBridge() }
}
