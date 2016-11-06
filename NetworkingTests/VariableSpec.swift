//
//  VariableSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
@testable import Networking

// TODO: add test for POSIXlt
class VariableSpec: NetworkingBaseSpec {
	override func spec() {
		let json = loadTestJson("variables")

		describe("variable testing") {
			let variableDict = try! json.getDictionary(at: "variables")
			var variables: [String: Variable] = [:]
			variableDict.forEach { (key, value) in
				do {
					try variables[key] = Variable.variableForJson(value)
				} catch {
					fatalError("failed to load \(value)")
				}
			}
			it("correct number of variables") {
				expect(variables.count).to(equal(11))
			}
			
			context("string") {
				expect(variables["str"]).toNot(beNil())
				let strVar = variables["str"]!
				let typeCheck = type(of: strVar) == StringPrimitiveVariable.self
				expect(typeCheck).to(beTrue())
				expect(strVar.length).to(equal(2))
				expect(strVar.isPrimitive).to(beTrue())
				expect(strVar.classNameR).to(equal("string"))
				expect(strVar.stringValueAtIndex(0)).to(equal("foo"))
				expect(strVar.stringValueAtIndex(1)).to(equal("bar"))
			}

			context("logic") {
				expect(variables["logic"]).toNot(beNil())
				let theVal = variables["logic"]!
				let typeCheck = type(of: theVal) == BoolPrimitiveVariable.self
				expect(typeCheck).to(beTrue())
				expect(theVal.length).to(equal(2))
				expect(theVal.isPrimitive).to(beTrue())
				expect(theVal.classNameR).to(equal("logical"))
				expect(theVal.boolValueAtIndex(0)).to(beTrue())
				expect(theVal.boolValueAtIndex(1)).to(beFalse())
			}

			context("double") {
				expect(variables["doubleVal"]).toNot(beNil())
				let theVal = variables["doubleVal"]!
				let typeCheck = type(of: theVal) == DoublePrimitiveVariable.self
				expect(typeCheck).to(beTrue())
				expect(theVal.length).to(equal(1))
				expect(theVal.isPrimitive).to(beTrue())
				expect(theVal.classNameR).to(equal("numeric vector"))
				expect(theVal.doubleValueAtIndex(0)).to(beCloseTo(12.1))
			}
			
			context("int") {
				expect(variables["intVal"]).toNot(beNil())
				let theVal = variables["intVal"]!
				let typeCheck = type(of: theVal) == IntPrimitiveVariable.self
				expect(typeCheck).to(beTrue())
				expect(theVal.length).to(equal(3))
				expect(theVal.isPrimitive).to(beTrue())
				expect(theVal.classNameR).to(equal("numeric vector"))
				expect(theVal.intValueAtIndex(0)).to(equal(1))
				expect(theVal.intValueAtIndex(1)).to(equal(3))
				expect(theVal.intValueAtIndex(2)).to(equal(4))
			}
			
			context("special numbers") {
				expect(variables["specialId"]).toNot(beNil())
				let theVal = variables["specialId"]!
				let typeCheck = type(of: theVal) == DoublePrimitiveVariable.self
				expect(typeCheck).to(beTrue())
				expect(theVal.length).to(equal(4))
				expect(theVal.isPrimitive).to(beTrue())
				expect(theVal.classNameR).to(equal("numeric vector"))
				expect(theVal.doubleValueAtIndex(0)?.isNaN).to(beTrue())
				expect(theVal.doubleValueAtIndex(1)).to(equal(Double.infinity))
				expect(theVal.doubleValueAtIndex(2)).to(equal(-Double.infinity))
			}

			context("posix ct") {
				expect(variables["dct"]).toNot(beNil())
				let theVal = variables["dct"]!
				expect(theVal.type).to(equal(VariableType.dateTime))
				guard let dateVal = theVal as? DateVariable else {
					fatalError()
				}
				expect(dateVal.classNameR).to(equal("POSIXct"))
				let expectedDate = Date(timeIntervalSince1970: 1462016050.3478991985)
				expect(dateVal.date.timeIntervalSince1970).to(beCloseTo(expectedDate.timeIntervalSince1970))
			}

			context("date") {
				expect(variables["date"]).toNot(beNil())
				let theVal = variables["date"]!
				expect(theVal.type).to(equal(VariableType.date))
				guard let dateVal = theVal as? DateVariable else {
					fatalError()
				}
				let expectedDate = DateVariable.dateFormatter.date(from: "1954/4/18")!
				expect(dateVal.date.timeIntervalSince1970).to(beCloseTo(expectedDate.timeIntervalSince1970))
				expect(dateVal.classNameR).to(equal("Date"))
			}
			
			context("factor") {
				expect(variables["f"]).toNot(beNil())
				let theVal = variables["f"]!
				expect(theVal.type).to(equal(VariableType.factor))
				let fval = theVal as! FactorVariable
				expect(fval.count).to(equal(6))
				expect(fval.intValueAtIndex(0)).to(equal(0))
				expect(fval.intValueAtIndex(2)).to(equal(2))
				expect(fval.stringValueAtIndex(0)).to(equal("a"))
				expect(fval.stringValueAtIndex(1)).to(equal("a"))
				expect(fval.stringValueAtIndex(2)).to(equal("c"))
			}

			context("complex") {
				expect(variables["cpx"]).toNot(beNil())
				let theVal = variables["cpx"]!
				expect(theVal.type).to(equal(VariableType.primitive))
				expect(theVal.primitiveType).to(equal(PrimitiveType.complex))
				expect(theVal.length).to(equal(2))
				expect (theVal.stringValueAtIndex(0)).to(equal("0.09899058348162+1.28356775897029i"))
			}

			context("complex") {
				expect(variables["cpx"]).toNot(beNil())
				let theVal = variables["cpx"]!
				expect(theVal.type).to(equal(VariableType.primitive))
				expect(theVal.primitiveType).to(equal(PrimitiveType.complex))
			}
			
			context("null") {
				expect(variables["nn"]).toNot(beNil())
				let theVal = variables["nn"]!
				expect(theVal.type).to(equal(VariableType.primitive))
				expect(theVal.primitiveType).to(equal(PrimitiveType.null))
				expect(theVal.primitiveValueAtIndex(0)).to(beNil())
			}
			
			//need to handle "r1" which is a raw value (not fully implemented on server)
		}
	}
}
