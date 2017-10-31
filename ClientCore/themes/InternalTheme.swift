//
//  InternalTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

enum ThemeError: Error {
	case notEditable
}

protocol InternalTheme: Theme {
	init(name: String)

	var name: String { get set }
	var colors: [Property: PlatformColor] { get set }
	var dirty: Bool { get set }

	func duplicate(name: String) -> Self
}

extension InternalTheme {
	func duplicate(name: String) -> Self {
		let other = type(of: self).init(name: name)
		other.colors = colors
		other.dirty = true
		return other
	}

	func save() throws {
		guard !isBuiltin else { throw ThemeError.notEditable }
	}

	private func savedThemeName() -> String? {
		guard var fileName = fileUrl?.lastPathComponent,
			let suffixRange = fileName.range(of: ".json")
			else { return nil }
		fileName.remove(at: suffixRange.lowerBound)
		return fileName
	}
}
