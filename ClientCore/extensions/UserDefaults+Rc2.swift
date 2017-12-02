//
//  UserDefaults+JSON.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import SwiftyUserDefaults
import MJLLogger

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
				Log.warn("error saving a JSON object to UserDefaults: \(err)", .core)
			}
		}
	}

	//allow storing font descriptors
	public subscript(key: DefaultsKey<FontDescriptor?>) -> FontDescriptor? {
		get {
			guard let data = data(forKey: key._key), let fdesc = NSUnarchiver.unarchiveObject(with: data) as? FontDescriptor else {
				return nil
			}
			return fdesc
		}
		set {
			guard let fdesc = newValue else {
				remove(key._key)
				return
			}
			set(NSArchiver.archivedData(withRootObject: fdesc), forKey: key._key)
		}
	}
	
	public subscript(key: DefaultsKey<CGFloat>) -> CGFloat {
		get {
			return CGFloat(double(forKey: key._key))
		}
		set {
			set(Double(newValue), forKey: key._key)
		}
	}
}
