//
//  URLResponse+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension URLResponse {
	///returns self as HTTPURLResponse to remove casting
	var httpResponse: HTTPURLResponse? { return self as? HTTPURLResponse }
}
