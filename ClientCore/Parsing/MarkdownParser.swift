//
//  MarkdownParser.swift
//  ClientCore
//
//  Created by Mark Lilback on 11/19/20.
//  Copyright © 2020 Rc2. All rights reserved.
//

import Foundation

public class MarkdownParser {
	let allocator: UnsafeMutablePointer<cmark_mem>
	let cmarkOptions = CMARK_OPT_SOURCEPOS | CMARK_OPT_FOOTNOTES
	let parser: UnsafeMutablePointer<cmark_parser>?
	let extensions: UnsafeMutablePointer<cmark_llist>? = nil
	
	public init() {
		allocator = cmark_get_default_mem_allocator()
		parser = cmark_parser_new(cmarkOptions)
		let tableExtension = cmark_find_syntax_extension("table")
		let strikeExtension = cmark_find_syntax_extension("strikethrough")
		cmark_llist_append(allocator, extensions, tableExtension)
		cmark_llist_append(allocator, extensions, strikeExtension)
	}
	
	public func htmlFor(markdown: String) -> NSMutableString {
		markdown.withCString( { chars in
			cmark_parser_feed(parser, chars, strlen(chars))
		})
		let htmlDoc = cmark_parser_finish(parser)
		let html = NSMutableString(cString: cmark_render_html_with_mem(htmlDoc, cmarkOptions, extensions, allocator), encoding: String.Encoding.utf8.rawValue)!
		return html
	}
	
	deinit {
		cmark_llist_free(allocator, extensions)
		cmark_parser_free(parser)
	}
}

