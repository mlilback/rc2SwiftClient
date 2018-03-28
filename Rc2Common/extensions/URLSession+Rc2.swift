//
//  URLSession+Rc2.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Result

public extension URLSession {
	/// Performs a dataTask on session with request
	///
	/// - Parameters:
	///   - request: the GET request to perform
	/// - Returns: SignalProducer with data or an error. Error will be .network with no nested error if a non 2XX status code is returned or no data is returned
	public func getData(request: URLRequest) -> SignalProducer<Data, Rc2Error> {
		return SignalProducer<Data, Rc2Error> { observer, _ in
			let task = self.dataTask(with: request, completionHandler: { (data, response, error) in
				if let error = error {
					observer.send(error: Rc2Error(type: .cocoa, nested: error))
					return
				}
				guard let data = data, let code = response?.httpResponse?.statusCode, code < 299 else {
					observer.send(error: Rc2Error(type: .network, explanation: "server returned no data"))
					return
				}
				observer.send(value: data)
				observer.sendCompleted()
			})
			task.resume()
		}
	}
}
