//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger

public extension LogCategory {
	static let network: LogCategory = LogCategory("network")
	static let docker: LogCategory = LogCategory("docker")
	static let dockerEvt: LogCategory = LogCategory("docker-evt")
	static let model: LogCategory = LogCategory("model")
	static let session: LogCategory = LogCategory("session")
	static let core: LogCategory = LogCategory("core")
	static let app: LogCategory = LogCategory("app")
	static let cache: LogCategory = LogCategory("cache")
	static let parser: LogCategory = LogCategory("parser")
	
	static let allRc2Categories: [LogCategory] = [.app, .session, .model, .network, .core, .cache, .parser, .docker, .dockerEvt]
}

public let defaultAppServerPort = 3145
