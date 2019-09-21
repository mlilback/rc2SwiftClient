//
//  UserDefaults+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyUserDefaults
import MJLLogger

extension FontDescriptor: DefaultsSerializable {
}

extension CGFloat: DefaultsSerializable {
	public static var _defaults: DefaultsBridge<Double> { return DefaultsDoubleBridge() }
	public static var _defaultsArray: DefaultsBridge<[Double]> { return DefaultsArrayBridge() }
}
