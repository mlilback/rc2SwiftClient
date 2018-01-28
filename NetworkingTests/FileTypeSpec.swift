//
//  FileTypeSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
@testable import Model

class FileTypeSpec: QuickSpec {
	override func spec() {
		describe("file types are loaded correctly") {
		it("correct number of types") {
				expect(FileType.allFileTypes.count).to(equal(10))
			}
		}
		
		it("Rmd type is valid") {
			let rawRmd = FileType.fileType(withExtension: "Rmd")
			expect(rawRmd).toNot(beNil())
			let rmd = rawRmd!
			expect(rmd.name).to(equal("R markdown"))
			expect(rmd.isExecutable).to(beTrue())
			expect(rmd.isCreatable).to(beTrue())
			expect(rmd.isImage).to(beFalse())
			expect(rmd.isImportable).to(beTrue())
			expect(rmd.isSource).to(beTrue())
			expect(rmd.mimeType).to(equal("text/plain"))
			expect(rmd.uti).to(equal("org.r-project.Rmd"))
		}

		it("png type is valid") {
			let rawType = FileType.fileType(withExtension: "png")
			expect(rawType).toNot(beNil())
			let type = rawType!
			expect(type.name).to(equal("PNG image"))
			expect(type.isExecutable).to(beFalse())
			expect(type.isCreatable).to(beFalse())
			expect(type.isImage).to(beTrue())
			expect(type.isImportable).to(beFalse())
			expect(type.isSource).to(beFalse())
			expect(type.mimeType).to(equal("image/png"))
			expect(type.uti).to(equal(kUTTypePNG as String))
		}
	}
}
