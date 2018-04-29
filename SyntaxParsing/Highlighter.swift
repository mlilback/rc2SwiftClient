//
//  BaseHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import Rc2Common	// required for theme = Property(ThemeManager...)

/// Highlights by adding fore- and backgroundColors to an attributedString, based
/// on custom attributes provided by the SyntaxParser (FragmentType & ChunkType).
public func highlight(attributedString attStr: NSMutableAttributedString,
					  inRange: NSRange? = nil,
					  theme: SyntaxTheme = ThemeManager.shared.activeSyntaxTheme.value) {
	// Default range in the full range of attStr:
	let range = (inRange != nil) ? inRange! : attStr.string.fullNSRange
	// Remove previous fore- and backgroundColors
	attStr.removeAttribute(.foregroundColor, range: range)
	attStr.removeAttribute(.backgroundColor, range: range)
	// Iterate through all attributes and switch and highlight based on type:
	attStr.enumerateAttributes(in: range, options: []) { (keyValues, attRange, stop) in
		// Highlight fragment foregroundColor:
		if let fragmentType = keyValues[FragmentTypeKey] as? FragmentType {
			switch fragmentType {
			case .none:
				break
			case .quote:
				attStr.addAttribute(.foregroundColor, value: theme.color(for: .quote), range: attRange)
			case .comment:
				attStr.addAttribute(.foregroundColor, value: theme.color(for: .comment), range: attRange)
			case .keyword:
				attStr.addAttribute(.foregroundColor, value: theme.color(for: .keyword), range: attRange)
			case .symbol:
				attStr.addAttribute(.foregroundColor, value: theme.color(for: .symbol), range: attRange)
			case .number:
				break
			}
		}
		// Highlight chunk backgroundColor:
		if let chunkType = keyValues[ChunkTypeKey] as? ChunkType {
			switch chunkType {
			case .code:
				attStr.addAttribute(.backgroundColor, value: theme.color(for: .codeBackground), range: attRange)
			case .equation:
				attStr.addAttribute(.backgroundColor, value: theme.color(for: .equationBackground), range: attRange)
			case .docs:
				break
			}
		}
	}
}

