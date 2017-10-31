//
//  BookmarkManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import SwiftyUserDefaults
import os

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let bookmarks = DefaultsKey<Data?>("Bookmarks")
	static let hosts = DefaultsKey<Data?>("ServerHosts")
}

///manages access to Bookmarks and ServerHosts
public class BookmarkManager {
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()
	///all existing bookmarks
	public fileprivate(set) var bookmarks: [Bookmark] = []
	///bookmarks grouped by ServerHost.name
	public fileprivate(set) var bookmarkGroups: [String: BookmarkGroup] = [:]
	///all known ServerHosts
	public fileprivate(set) var hosts: [ServerHost] = []
	
	public init() {
		loadBookmarks()
	}
	
	///saves bookmarks and hosts to NSUserDefaults
	public func save() {
		do {
			let defaults = UserDefaults.standard
			defaults[.bookmarks] = try encoder.encode(bookmarks)
			defaults[.hosts] = try encoder.encode(hosts)
		} catch {
			os_log("error saving bookmarks: %{public}@", log: .app, error.localizedDescription)
		}
	}
	
	///adds a new bookmark to bookmarks array
	/// - parameter bookmark: the bookmark to add
	public func addBookmark(_ bookmark: Bookmark) {
		bookmarks.append(bookmark)
		addBookmarkToAppropriateGroup(bookmark)
		bookmarks.sort()
	}
	
	///replaces an existing bookmark (when edited)
	/// - parameter old: the bookmark to replace
	/// - parameter with: the replacement bookmark
	/// - returns: true if old was found and replaced
	@discardableResult
	public func replaceBookmark(_ old: Bookmark, with new: Bookmark) -> Bool {
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
		if let data = defaults[.bookmarks], let bmarks = try? decoder.decode([Bookmark].self, from: data)
		{
			bookmarks.append(contentsOf: bmarks)
		}
		if bookmarks.count < 1 {
			bookmarks = createDefaultBookmarks()
		}
		bookmarks.sort()
		groupBookmarks()
		loadHosts()
	}
	
	fileprivate func groupBookmarks() {
		bookmarkGroups.removeAll()
		for aMark in bookmarks {
			addBookmarkToAppropriateGroup(aMark)
		}
	}
	
	fileprivate func addBookmarkToAppropriateGroup(_ bookmark: Bookmark) {
		let localKey: String = bookmark.server?.name ?? NetworkConstants.localBookmarkGroupName
		if let _ = bookmarkGroups[localKey] {
			bookmarkGroups[localKey]!.addBookmark(bookmark)
		} else {
			bookmarkGroups[localKey] = BookmarkGroup(key: localKey, firstBookmark: bookmark)
		}
	}
	
	///add a server host
	/// - parameter host: the host to add
	public func addHost(_ host: ServerHost) {
		hosts.append(host)
		hosts.sort { $0.name < $1.name }
	}
	
	///loads hosts from NSUserDefaults
	fileprivate func loadHosts() {
		let defaults = UserDefaults.standard
		var hostSet = Set<ServerHost>()
		hosts.removeAll()
		if let data = defaults[.hosts],
			let hostArray = try? decoder.decode([ServerHost].self, from: data)
		{
			hostSet = hostSet.union(hostArray)
		}
		for aMark in bookmarks where aMark.server != nil {
			hostSet.insert(aMark.server!)
		}
		hosts.append(contentsOf: hostSet)
		hosts.sort { $0.name < $1.name }
	}
	
	///returns an array of default bookmarks
	fileprivate func createDefaultBookmarks() -> [Bookmark] {
		return [Bookmark.defaultBookmark]
	}
}

///represents a collection of Bookmarks grouped by a key
public struct BookmarkGroup {
	public let key: String
	public private(set) var bookmarks: [Bookmark] = []
	
	public init(key: String, firstBookmark: Bookmark? = nil) {
		self.key = key
		if firstBookmark != nil { bookmarks.append(firstBookmark!) }
	}
	
	public init(original: BookmarkGroup) {
		self.key = original.key
		self.bookmarks = original.bookmarks
	}
	
	public mutating func addBookmark(_ bmark: Bookmark) {
		bookmarks.append(bmark)
	}
}
