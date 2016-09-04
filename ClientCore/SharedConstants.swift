//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

let Rc2ErrorDomain = "Rc2ErrorDomain"

///localizedDescription will be looked up based on the key Rc2ErrorCode.(enum label)
public enum Rc2ErrorCode: Int {
	case ServerError = 101
	case Impossible = 102
	case DockerError = 103
	case NoSuchProject = 104
	case NetworkError = 105
}
