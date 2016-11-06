//
//  FileTypeSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
@testable import Networking

class FileTypeSpec: QuickSpec {
	override func spec() {
		describe("file types are loaded correctly") {
		it("correct number of types") {
				expect(FileType.allFileTypes.count).to(equal(11))
			}
		}
		
		it("Rmd type is valid") {
			let rawRmd = FileType.fileType(withExtension: "Rmd")
			expect(rawRmd).toNot(beNil())
			let rmd = rawRmd!
			expect(rmd.name).to(equal("R markdown"))
			expect(rmd.isTextFile).to(beTrue())
			expect(rmd.isRMarkdown).to(beTrue())
			expect(rmd.isExecutable).to(beTrue())
			expect(rmd.isCreatable).to(beTrue())
			expect(rmd.isImage).to(beFalse())
			expect(rmd.isImportable).to(beTrue())
			expect(rmd.isSourceFile).to(beTrue())
			expect(rmd.isSweave).to(beFalse())
			expect(rmd.mimeType).to(equal("text/plain"))
		}

		it("png type is valid") {
			let rawType = FileType.fileType(withExtension: "png")
			expect(rawType).toNot(beNil())
			let type = rawType!
			expect(type.name).to(equal("PNG image"))
			expect(type.isTextFile).to(beFalse())
			expect(type.isRMarkdown).to(beFalse())
			expect(type.isExecutable).to(beFalse())
			expect(type.isCreatable).to(beFalse())
			expect(type.isImage).to(beTrue())
			expect(type.isImportable).to(beFalse())
			expect(type.isSourceFile).to(beFalse())
			expect(type.isSweave).to(beFalse())
			expect(type.mimeType).to(equal("image/png"))
		}
	}
}
