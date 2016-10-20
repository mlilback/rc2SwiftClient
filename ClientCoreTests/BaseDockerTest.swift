//
//  BaseDockerTest.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import ClientCore
import SwiftyJSON
import BrightFutures
import Mockingjay
import Result

class BaseDockerTest: XCTestCase {
	var userDefaults: UserDefaults!
	var sessionConfig:URLSessionConfiguration!
	
	override func setUp() {
		super.setUp()
		sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		userDefaults = UserDefaults(suiteName: UUID().uuidString)! //not sure why this is failable
	}

	@available(*, deprecated)
	func callDockerMethod(docker:DockerManager?, action: @escaping (DockerManager) -> Future<Bool,NSError>) -> Result<Bool, NSError>?
	{
		var dm:DockerManager? = docker
		if dm == nil {
			dm = DockerManager(userDefaults:userDefaults, sessionConfiguration:sessionConfig)
		}
		let expect = expectation(description: "calling a docker method")
		var result: Result<Bool, NSError>?
//		dm!.initializeConnection().flatMap { r1 in
//			action(dm!)
//			}.onComplete { r2 in
//				result = r2
//				expect.fulfill()
//		}
//		waitForExpectations(timeout: 10) { _ in }
		return result
	}
	
	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: type(of:self)).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(uri(uri: uriPath), builder: jsonData(resultData!))
	}
}

