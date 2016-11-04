//
//  FileSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
@testable import Networking

class FileSpec: NetworkingBaseSpec {
	override func spec() {
		let loginResultsJson = loadTestJson("loginResults")
		let file = try! loginResultsJson.decode(at: "projects", 0, "workspaces", 0, "files", 0, type: File.self)
		
		describe("test File type") {
			it("file should encapsulate values from json") {
				expect(file.fileId) == 1
				expect(file.name) == "sample.R"
				expect(file.version) == 0
				expect(file.fileSize) == 28
				expect(file.fileType.fileExtension) == "R"
				expect(file.dateCreated.timeIntervalSince1970).to(beCloseTo(1439407405, within: 1))
				expect(file.lastModified.timeIntervalSince1970).to(beCloseTo(1439407505, within: 1))
			}
		}
	}
}
