//
//  UserDefaults+JSON.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import SwiftyUserDefaults
import os

public extension UserDefaults {
	///allow storing JSON objects via SwiftyUserDefaults (serialized as Data)
	public subscript(key: DefaultsKey<JSON?>) -> JSON? {
		get {
			guard let data = data(forKey: key._key) else { return nil }
			return JSON(data: data)
		}
		set {
			do {
				set(try newValue?.rawData(), forKey: key._key)
			} catch let err {
				os_log("error saving a JSON object to UserDefaults:%{public}s", err as NSError)
			}
		}
	}
}

