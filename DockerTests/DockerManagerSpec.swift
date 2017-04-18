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
@testable import Docker

class DockerManagerSpec: BaseDockerSpec {
	override func spec() {
		describe("test docker manager") {
			let compute42Id = "sha256:26b540e285dfef430d183b0677151dc371a7553df326777e96d43f1af61897d1"
			let compute43Id = "sha256:12f22a6ac93151274b28590a95cb0debd049c3aa6141287a864ca3205a4cad8c"
			var dockerM: DockerManager?
			var sessionConfig: URLSessionConfiguration!

			// to properly stub out DockerManager.initialize, need to
			// stub /version
			// inject implementation of DockerEventMonitor
			// stub /volumes for volumeExists(_)
			// stub /networks for networkExists(_)
			// stub /images/json for loadImages()
			// defaults passed to DM.init needs to have lastImageInfoCheck set to Date.distantFuture.timeIntervalSinceReferenceDate

			beforeEach {
				sessionConfig = URLSessionConfiguration.default
				//if DUP isn't there, DM will add it to front of array. We need MJ before it, even though MJ will have put itself there already
				sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
				let defaults = UserDefaults()
				defaults[.lastImageInfoCheck] = Date.distantFuture.timeIntervalSinceReferenceDate
				dockerM = DockerManager(hostUrl: nil, baseInfoUrl: "http://foo.com/", userDefaults: defaults, sessionConfiguration: sessionConfig)
				dockerM?.eventMonitorClass = DummyEventMonitor.self
				self.stubDockerGetRequest(uriPath: "/version", fileName: "version")
				self.stubDockerGetRequest(uriPath: "/networks", fileName: "networks")
				self.stubDockerGetRequest(uriPath: "/volumes", fileName: "volumes")
				self.stubDockerGetRequest(uriPath: "/images/json", fileName: "complexImages")
				self.stubDockerGetRequest(uriPath: "/imageInfo.json", fileName: "updatedImageInfo")
			}
			
			let testMergeContainers = { (old: [DockerContainer], new: [DockerContainer]) -> [DockerContainer] in
				///confirm mergeContainers() works properly
				let mergedResult = self.makeValueRequest(producer: dockerM!.mergeContainers(newContainers: new, oldContainers: old), queue: .global())
				expect(mergedResult.error).to(beNil())
				let mergedContainers = mergedResult.value!
				expect(mergedContainers[.compute]?.imageId).to(equal(compute43Id))
				return mergedContainers
			}
			
			let testRemoveOutdatedContainers = { (containers: [DockerContainer]) in
				let containerName = containers[.compute]!.name
				//stub all deletes to fail
				self.stub({ request -> Bool in
					request.httpMethod == "DELETE"
				}, builder: http(404))
				//stub desired delete to succeed
				self.stub({ request -> Bool in
					request.httpMethod! == "DELETE" && request.url!.path == "/containers/\(containerName)"
				}, builder: http(204))
				self.stub(self.postMatcher(uriPath: "/containers/\(containerName)/stop"), builder: http(204))
				let outdatedProducer = dockerM!.removeOutdatedContainers(containers: containers)
				let outdatedResult = self.makeValueRequest(producer: outdatedProducer, queue: .global())
				expect(outdatedResult.error).to(beNil())
				expect(outdatedResult.value![.compute]!.state.value).to(equal(ContainerState.notAvailable))
			}
			
			let testRefreshContainers = { (fileName: String) -> Result<[DockerContainer], Rc2Error> in
				self.stubDockerGetRequest(uriPath: "/containers/json", fileName: fileName)
				let result = self.makeValueRequest(producer: dockerM!.api.refreshContainers(), queue: .global())
				expect (result.error).to(beNil())
				return result
			}
			
			let testInitialize = {
				guard let dm = dockerM else { fatalError() }
				///confirm dm is what we expect
				expect(dm.api).toNot(beNil())
				expect(dm.imageInfo!.version).to(equal(2))
				expect(dm.imageInfo!.computeserver.id).to(equal(compute42Id))

				///confirm .initialize() works
				let result = self.makeValueRequest(producer: dm.initialize(), queue: .global())
				expect(result.error).to(beNil())
			}

			//test that all stages of .initialize() and .prepareContainers() works properly
			it("dm prepare containers logic works") {
				testInitialize()

				//test refresh containers
				let cresults = testRefreshContainers("containers")
				let origContainers = cresults.value!
				expect(origContainers[.compute]?.imageId).to(equal(compute42Id))

				///confirm updated containers are what we expect
				let upresults = testRefreshContainers("updatedContainers")
				let newContainers = upresults.value!
				expect(newContainers[.compute]?.imageId).to(equal(compute43Id))

				let mergedContainers = testMergeContainers(origContainers, newContainers)
				testRemoveOutdatedContainers(mergedContainers)
			}

			it("checkForImageUpdate works") {
				testInitialize()
				expect(dockerM!.imageInfo!.timestampString).to(equal("2016-12-04T20:50:24Z"))
				self.stub({ (request) -> (Bool) in
					return request.httpMethod == "GET" && request.url!.path.hasSuffix("/imageInfo.json")
				}, builder: jsonData(self.resourceDataFor(fileName: "updatedImageInfo", fileExtension: "json")))
				let iiresult = self.makeValueRequest(producer: dockerM!.checkForImageUpdate(forceRefresh: true), queue: .global())
				expect(iiresult.error).to(beNil())
				expect(iiresult.value!).to(beTrue())
				expect(dockerM!.imageInfo!.timestampString).to(equal("2016-12-05T21:50:24Z"))
			}
		}
	}
}

class DummyEventMonitor: DockerEventMonitor {
	required init(baseUrl: URL, delegate: DockerEventMonitorDelegate, sessionConfig: URLSessionConfiguration)
	{
		
	}

}
