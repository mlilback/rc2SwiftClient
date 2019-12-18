//
//  Rc2RmdParser.swift
//  ClientCore
//
//  Created by Mark Lilback on 12/17/19.
//  Copyright © 2019 Rc2. All rights reserved.
//

import Foundation
import Rc2Parser
import ReactiveSwift

/// a callback that recieves a parsed keyword. returns true if a help URL should be included for it
public typealias HelpCallback = (String) -> Bool

/// for  instances where write access is not needed
public protocol ParserContext {
	var parsedDocument: Property<RmdDocument?> { get }
}

/// A wrapper around parsing so users of ClientCore do not need to know about Rc2Parser
public class Rc2RmdParser: RmdParser, ParserContext {
	var helpCallback: HelpCallback?
	private var contents: NSTextStorage
	// offers read-only version of _parsedDocument
	public let parsedDocument: Property<RmdDocument?>
	private let _parsedDocument = MutableProperty<RmdDocument?>(nil)
	
	
	public init(contents: NSTextStorage, help: @escaping HelpCallback) {
		self.contents = contents
		helpCallback = help
		parsedDocument = Property<RmdDocument?>(_parsedDocument)
	}
	
	public func highlight(text: NSMutableAttributedString, range: NSRange? = nil, delta: Int? = nil) {
		
	}

	public func selectionChanged(range: NSRange) {
		
	}
	
	/// Called when the contents of the editor have changed due to user action. By default, this parses and highlights the entire contents
	///
	/// - Parameters:
	///   - contents: The contents of the editor that was changed
	///   - range: the range of the original text that changed
	///   - delta: the length delta for the edited change
	public func contentsChanged(range: NSRange, changeLength delta: Int) {
		highlight(text: contents, range: range, delta: delta)
	}
}
