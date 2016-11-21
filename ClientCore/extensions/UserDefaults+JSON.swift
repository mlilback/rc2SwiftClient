//
//  UserDefaults+JSON.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import SwiftyUserDefaults
import os

public extension UserDefaults {
	///allow storing JSON objects via SwiftyUserDefaults (serialized as Data)
	public subscript(key: DefaultsKey<JSON?>) -> JSON? {
		get {
			guard let data = data(forKey: key._key), let json = try? JSON(data: data) else {
				return nil
			}
			return json
		}
		set {
			do {
				set(try newValue?.serialize(), forKey: key._key)
			} catch let err {
				os_log("error saving a JSON object to UserDefaults:%{public}s", log: .core, err as NSError)
			}
		}
	}
}
