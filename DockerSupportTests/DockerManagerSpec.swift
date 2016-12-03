//
//  DockerManagerSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Mockingjay
import Result
import Freddy
import SwiftyUserDefaults
import ClientCore
@testable import DockerSupport

class DockerManagerSpec: BaseDockerSpec {
	override func spec() {
		describe("test basic methods") {
			var sessionConfig: URLSessionConfiguration!
			beforeEach {
				sessionConfig = URLSessionConfiguration.default
				//if DUP isn't there, DM will add it to front of array. We need MJ before it, even though MJ will have put itself there already
				sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
			}

			// to properly stub out DockerManager.initialize, need to
			// stub /version
			// inject implementation of DockerEventMonitor
			// stub /volumes for volumeExists(_)
			// stub /networks for networkExists(_)
			// stub /images/json for loadImages()
			// defaults passed to DM.init needs to have lastImageInfoCheck set to Date.distantFuture.timeIntervalSinceReferenceDate
			// stub www.rc2.io/imageInfo.json
			
			//TODO: need mock userDefaults
//			it("manager can be created") {
//				let dm = DockerManager()
//				expect(dm).toNot(beNil())
//			}
			
			context("stubbed DM") {
				var dockerM: DockerManager?
				beforeEach {
					let defaults = UserDefaults()
					defaults[.lastImageInfoCheck] = Date.distantFuture.timeIntervalSinceReferenceDate
					dockerM = DockerManager(hostUrl: nil, baseInfoUrl: "foo.com", userDefaults: defaults, sessionConfiguration: sessionConfig)
					dockerM?.eventMonitorClass = DummyEventMonitor.self
					self.stubDockerGetRequest(uriPath: "/version", fileName: "version")
					self.stubDockerGetRequest(uriPath: "/networks", fileName: "networks")
					self.stubDockerGetRequest(uriPath: "/volumes", fileName: "volumes")
					self.stubDockerGetRequest(uriPath: "/images/json", fileName: "complexImages")
					self.stubDockerGetRequest(uriPath: "/imageInfo.json", fileName: "updatedImageInfo")
				}
				
				it("dm prepare containers logic works") {
					let compute42Id = "sha256:26b540e285dfef430d183b0677151dc371a7553df326777e96d43f1af61897d1"
					let compute43Id = "sha256:12f22a6ac93151274b28590a95cb0debd049c3aa6141287a864ca3205a4cad8c"
					guard let dm = dockerM else { fatalError() }
					///confirm dm is what we expect
					expect(dm.api).toNot(beNil())
					expect(dm.imageInfo!.version).to(equal("2016120101"))
					expect(dm.imageInfo!.computeserver.id).to(equal(compute42Id))
					///confirm .initialize() works
					let result = self.makeValueRequest(producer: dm.initialize(), queue: .global())
					expect(result.error).to(beNil())
					self.stubDockerGetRequest(uriPath: "/containers/json", fileName: "containers")
					let cresults = self.makeValueRequest(producer: dm.api.refreshContainers(), queue: DispatchQueue.global())
					expect (cresults.error).to(beNil())
					let origContainers = cresults.value!
					expect(origContainers[.compute]?.imageId).to(equal(compute42Id))
//					let iiresult = self.makeValueRequest(producer: dm.checkForImageUpdate(forceRefresh: true), queue: DispatchQueue.global())
//					expect(iiresult.error).to(beNil())
//					expect(dm.imageInfo!.version).to(equal("2016120201"))
					///confirm updated containers are what we expect
					self.stubDockerGetRequest(uriPath: "/containers/json", fileName: "updatedContainers")
					let upresults = self.makeValueRequest(producer: dm.api.refreshContainers(), queue: .global())
					expect (upresults.error).to(beNil())
					let newContainers = upresults.value!
					expect(newContainers[.compute]?.imageId).to(equal(compute43Id))
					///confirm mergeContainers() works properly
					let mergedResult = self.makeValueRequest(producer: dm.mergeContainers(newContainers: newContainers, oldContainers: origContainers), queue: .global())
					expect(mergedResult.error).to(beNil())
					let mergedContainers = mergedResult.value!
					expect(mergedContainers[.compute]?.imageId).to(equal(compute43Id))
					///confirm removeOutdatedContianers() returns proper signal producer
//					let outdatedProducer = dm.removeOutdatedContainers(containers: mergedContainers)
					//expect(out)
				}
			}
		}
	}
}

class DummyEventMonitor: DockerEventMonitor {
	required init(baseUrl: URL, delegate: DockerEventMonitorDelegate, sessionConfig: URLSessionConfiguration)
	{
		
	}

}
