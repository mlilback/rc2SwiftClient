//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger

public extension LogCategory {
	public static let network: LogCategory = LogCategory("network")
	public static let docker: LogCategory = LogCategory("docker")
	public static let dockerEvt: LogCategory = LogCategory("docker-evt")
	public static let model: LogCategory = LogCategory("model")
	public static let session: LogCategory = LogCategory("session")
	public static let core: LogCategory = LogCategory("core")
	public static let app: LogCategory = LogCategory("app")
	public static let cache: LogCategory = LogCategory("cache")
	public static let parser: LogCategory = LogCategory("parser")
	
	public static let allRc2Categories: [LogCategory] = [.app, .session, .model, .network, .core, .cache, .parser, .docker, .dockerEvt]
}

public let defaultAppServerPort = 3145
