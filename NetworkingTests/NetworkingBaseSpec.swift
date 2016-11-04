//
//  NetworkingBaseSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import Freddy

class NetworkingBaseSpec: QuickSpec {
	/// Load and parse a json file
	///
	/// - Parameter fileName: name of the file without the ".json"
	/// - Returns: the parsed json
	func loadTestJson(_ fileName: String) -> JSON {
		let bundle = Bundle(for: type(of: self))
		guard let url = bundle.url(forResource: fileName, withExtension: "json"),
			let data = try? Data(contentsOf: url),
			let json = try? JSON(data: data)
		else
		{
			fatalError("failed to load \(fileName).json")
		}
		return json
	}
}
