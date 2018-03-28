//
//  PlatformTypeAliases.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
	public typealias FontDescriptor = NSFontDescriptor
#else
	import UIKit
	public typealias FontDescriptor = UIFontDescriptor
#endif
