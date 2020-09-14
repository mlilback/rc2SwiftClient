//
//  Data+Rc2Spec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
@testable import Rc2Common

class DataRc2Spec: QuickSpec {
	override func spec() {
		let newline = Data([UInt8(10)])
		let data1Array: [UInt8] = [31, 33, 35, 59]
		let data1 = Data(data1Array)
		
		describe("enumerateComponentsSeparated") {
			it("handles empty data") {
				var count = 0
				Data().enumerateComponentsSeparated(by: newline) { _ in
					count += 1
				}
				expect(count).to(equal(0))
			}

			it("handles data without the separator") {
				var count = 0
				data1.enumerateComponentsSeparated(by: newline) { _ in
					count += 1
				}
				expect(count).to(equal(1))
			}

			it("handles data with 1 separator") {
				var count = 0
				var data = data1
				data.append(newline)
				data.append(data1)
				data.enumerateComponentsSeparated(by: newline) { _ in
					count += 1
				}
				expect(count).to(equal(2))
			}

			it("handles data with 1 separator and no more data") {
				var count = 0
				var data = data1
				data.append(newline)
				data.enumerateComponentsSeparated(by: newline) { _ in
					count += 1
				}
				expect(count).to(equal(1))
			}

			it("handles data with multiple separators and no more data") {
				var count = 0
				var data = data1
				data.append(newline)
				data.append(data1)
				data.append(newline)
				data.append(data1)
				data.enumerateComponentsSeparated(by: newline) { _ in
					count += 1
				}
				expect(count).to(equal(3))
			}

			it("handles data with multiple separators including empty ones") {
				var count = 0
				var data = data1
				data.append(newline)
				data.append(newline)
				data.append(data1)
				data.enumerateComponentsSeparated(by: newline) { _ in
					count += 1
				}
				expect(count).to(equal(3))
			}
		}
		
		describe("inputStream init") {
			
			it("handles block of data") {
				let inStream = InputStream(data: data1)
				let readData = Data(inStream)
				expect(readData).to(equal(data1))
			}
		}
	}
}
