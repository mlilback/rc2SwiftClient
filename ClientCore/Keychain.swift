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
public class Keychain {
	let service: String
	
	init(service: String = "io.rc2.client") {
		self.service = service
	}
	
	public func getString(key: String) -> String? {
		let query = setupQuery(key)
		var dataRef: AnyObject?
		let status = withUnsafeMutablePointer(&dataRef) { SecItemCopyMatching(query as CFDictionaryRef, UnsafeMutablePointer($0)) }
		if status == noErr && dataRef != nil {
			return NSString(data: (dataRef as? NSData)!, encoding: NSUTF8StringEncoding) as String?
		}
		return nil
	}
	
	public func removeKey(key: String) -> Bool {
		let query = setupQuery(key)
		return noErr == SecItemDelete(query)
	}
	
	public func setString(key: String, value: String?) throws {
		guard value != nil else {
			removeKey(key)
			return
		}
		var query = setupQuery(key)
		var status : OSStatus = noErr
		if let existing = getString(key) {
			guard existing != value else {
				return
			}
			let values: [String:AnyObject] = [SecValueData: (value?.dataUsingEncoding(NSUTF8StringEncoding))!]
			status = SecItemUpdate(query, values)
		} else {
			query[SecValueData] = value!.dataUsingEncoding(NSUTF8StringEncoding)
			status = SecItemAdd(query, nil)
		}
		if status != errSecSuccess {
			throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
		}
	}
	
	private func setupQuery(key:String) -> [String:AnyObject] {
		var query: [String:AnyObject] = [SecClass:kSecClassGenericPassword as String]
		query[kSecAttrService as String] = service
		query[kSecAttrAccount as String] = key
		query[kSecReturnData as String] = kCFBooleanTrue
		return query
	}
}