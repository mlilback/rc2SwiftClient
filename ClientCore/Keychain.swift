//
//  Keychain.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Security

private let SecClass: String! = kSecClass as String
private let SecAttrService: String! = kSecAttrService as String
private let SecAttrGeneric: String! = kSecAttrGeneric as String
private let SecAttrAccount: String! = kSecAttrAccount as String
private let SecValueData: String! = kSecValueData as String
open class Keychain {
	let service: String

	init(service: String = "io.rc2.client") {
		self.service = service
	}

	open func getString(_ key: String) -> String? {
		let query = setupQuery(key)
		var dataRef: AnyObject?
		let status = withUnsafeMutablePointer(to: &dataRef) { SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0)) }
		if status == noErr && dataRef != nil {
			return NSString(data: (dataRef as? Data)!, encoding: String.Encoding.utf8.rawValue) as String?
		}
		return nil
	}

	@discardableResult open func removeKey(_ key: String) -> Bool {
		let query = setupQuery(key)
		return noErr == SecItemDelete(query as CFDictionary)
	}

	open func setString(_ key: String, value: String?) throws {
		guard value != nil else {
			removeKey(key)
			return
		}
		var query = setupQuery(key)
		var status: OSStatus = noErr
		if let existing = getString(key) {
			guard existing != value else {
				return
			}
			let values: [String:AnyObject] = [SecValueData: (value?.data(using: String.Encoding.utf8))! as AnyObject]
			status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
		} else {
			query[SecValueData] = value!.data(using: String.Encoding.utf8) as AnyObject?
			status = SecItemAdd(query as CFDictionary, nil)
		}
		if status != errSecSuccess {
			throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
		}
	}

	fileprivate func setupQuery(_ key: String) -> [String:AnyObject] {
		var query: [String: AnyObject] = [SecClass: kSecClassGenericPassword as String as String as AnyObject]
		query[kSecAttrService as String] = service as AnyObject?
		query[kSecAttrAccount as String] = key as AnyObject?
		query[kSecReturnData as String] = kCFBooleanTrue
		return query
	}
}
