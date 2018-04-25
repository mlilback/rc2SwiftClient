//
//  NotebookItemData.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SyntaxParsing
import ReactiveSwift

public class NotebookItemData: NSObject {
	private var _source: NSAttributedString
	
	/// sets to a copy if assigned value is NSMutableAttributedString
	@objc public var source: NSAttributedString {
		get { return _source }
		set {
			_source = newValue is NSMutableAttributedString ? NSAttributedString(attributedString: newValue) : newValue
			chunk.contents = _source //this will do syntax highlighting
			_source = chunk.contents
		}
	}
	/// sets to a copy if assigned value is NSMutableAttributedString
	@objc public var result: NSAttributedString { didSet {
		if source is NSMutableAttributedString {
			source = NSAttributedString(attributedString: source)
		}
	}}
	@objc public var height: CGFloat = 40
	public var chunk: RmdChunk
	/// this is bookkeeping for NotebookViewItem and is meant to be used by it
	public let resultsVisible = MutableProperty(true)

	public init(chunk: RmdChunk, result: String) {
		self.chunk = chunk
		self._source = chunk.contents
		self.result = NSAttributedString(string: result)
		super.init()
	}
}
