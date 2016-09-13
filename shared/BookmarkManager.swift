//
//  BookmarkManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import os

///manages access to Bookmarks and ServerHosts
open class BookmarkManager {
	///all existing bookmarks
	fileprivate(set) var bookmarks: [Bookmark] = []
	///bookmarks grouped by ServerHost.name
	fileprivate(set) var bookmarkGroups: [String:BookmarkGroup] = [:]
	///all known ServerHosts
	fileprivate(set) var hosts: [ServerHost] = []
	
	init() {
		loadBookmarks()
	}

	///saves bookmarks and hosts to NSUserDefaults
	func save() {
		let defaults = UserDefaults.standard
		do {
			let bmarks = try JSON(bookmarks.map() { try $0.serialize() })
			defaults.set(bmarks.rawString(), forKey: PrefKeys.Bookmarks)
			let jhosts = try JSON(hosts.map() { try $0.serialize() })
			defaults.set(jhosts.rawString(), forKey: PrefKeys.Hosts)
		} catch let err as NSError {
			os_log("failed to serialize bookmarks: %{public}@", type:.error, err)
		}
	}
	
	///adds a new bookmark to bookmarks array
	/// - parameter bookmark: the bookmark to add
	func addBookmark(_ bookmark:Bookmark) {
		bookmarks.append(bookmark)
		addBookmarkToAppropriateGroup(bookmark)
		bookmarks.sort() { $0.name < $1.name }
	}
	
	///replaces an existing bookmark (when edited)
	/// - parameter old: the bookmark to replace
	/// - parameter with: the replacement bookmark
	/// - returns: true if old was found and replaced
	@discardableResult func replaceBookmark(_ old:Bookmark, with new:Bookmark) -> Bool {
		if let idx = bookmarks.index(of: old) {
			bookmarks[idx] = new
			groupBookmarks()
			return true
		}
		return false
	}
	
	///loads bookmarks and hosts from NSUserDefaults
	fileprivate func loadBookmarks() {
		let defaults = UserDefaults.standard
		bookmarks.removeAll()
		//load them, or create default ones
		if let bmstr = defaults.string(forKey: PrefKeys.Bookmarks) {
			for aJsonObj in JSON.parse(bmstr).arrayValue {
				bookmarks.append(Bookmark(json: aJsonObj)!)
			}
		}
		if bookmarks.count < 1 {
			bookmarks = createDefaultBookmarks()
		}
		bookmarks.sort() { $0.name < $1.name }
		groupBookmarks()
		loadHosts()
	}

	fileprivate func groupBookmarks() {
		bookmarkGroups.removeAll()
		for aMark in bookmarks {
			addBookmarkToAppropriateGroup(aMark)
		}
	}

	fileprivate func addBookmarkToAppropriateGroup(_ bookmark:Bookmark) {
		let localKey:String = bookmark.server?.name ?? Constants.LocalBookmarkGroupName
		if let _ = bookmarkGroups[localKey] {
			bookmarkGroups[localKey]!.addBookmark(bookmark)
		} else {
			bookmarkGroups[localKey] = BookmarkGroup(key: localKey, firstBookmark: bookmark)
		}
	}
	
	///add a server host
	/// - parameter host: the host to add
	func addHost(_ host:ServerHost) {
		hosts.append(host)
		hosts.sort() { $0.name < $1.name }
	}
	
	///loads hosts from NSUserDefaults
	fileprivate func loadHosts() {
		let defaults = UserDefaults.standard
		var hostSet = Set<ServerHost>()
		hosts.removeAll()
		if let hostsStr = defaults.string(forKey: PrefKeys.Hosts) {
			for aJsonObj in JSON.parse(hostsStr).arrayValue {
				hostSet.insert(ServerHost(json: aJsonObj)!)
			}
		}
		for aMark in bookmarks {
			if aMark.server != nil { hostSet.insert(aMark.server!) }
		}
		hosts.append(contentsOf: hostSet)
		hosts.sort() { $0.name < $1.name }
	}
	
	///returns an array of default bookmarks
	fileprivate func createDefaultBookmarks() -> [Bookmark] {
		let bmark = Bookmark(name:Constants.DefaultBookmarkName, server: nil, project: Constants.DefaultProjectName, workspace: Constants.DefaultWorkspaceName)
		return [bmark]
	}
}

///represents a collection of Bookmarks grouped by a key
struct BookmarkGroup {
	let key:String
	var bookmarks:[Bookmark] = []
	
	init(key:String, firstBookmark:Bookmark? = nil) {
		self.key = key
		if firstBookmark != nil { bookmarks.append(firstBookmark!) }
	}
	
	init(original:BookmarkGroup) {
		self.key = original.key
		self.bookmarks = original.bookmarks
	}
	
	mutating func addBookmark(_ bmark:Bookmark) {
		bookmarks.append(bmark)
	}
}

