//
//  URLStaleChecker.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import MJLLogger

/// allows checking to see if a url resource has changed
public class URLStateChecker: NSObject {
	fileprivate var session: URLSession!

	fileprivate static let lastModFormatter: DateFormatter = {
		var df = DateFormatter()
		df.locale = Locale(identifier: "en_POSIX")
		df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
		return df
	}()

	public init(config: URLSessionConfiguration = .ephemeral) {
		super.init()
		session = URLSession(configuration: config)
	}

	/// performs a request using the specified parameters
	///
	/// - Parameters:
	///   - url: the url to request
	///   - lastModified: the date for if-modified-since header
	///   - etag: the etag of last known version
	///   - handler: called with true if request returned 200
	public func check(url: URL, lastModified: Date? = nil, etag: String? = nil, handler: @escaping (Bool) -> Void)
	{
		let req = request(url: url, lastModified: lastModified, etag: etag)
		session.dataTask(with: req) { (_, response, error) in
			if let err = error {
				Log.warn("error checking http request: \(err)", .network)
				handler(false)
				return
			}
			if response?.httpResponse?.statusCode ?? 200 < 300 {
				handler(true)
			} else {
				handler(false)
			}
		}
	}

	/// performs a request using the specified paramaters
	///
	/// - Parameters:
	///   - url: the url to request
	///   - lastModified: the date for if-modified-since header
	///   - etag: the etag of last known version
	/// - Returns: signal producer that will provide a boolean or an error
	public func check(url: URL, lastModified: Date? = nil, etag: String? = nil) -> SignalProducer<Bool, Rc2Error>
	{
		return SignalProducer<Bool, Rc2Error> { observer, _ in
			let req = self.request(url: url, lastModified: lastModified, etag: etag)
			self.session.dataTask(with: req) { (_, response, error) in
				if let err = error {
					let rc2err = Rc2Error(type: .network, nested: err)
					observer.send(error: rc2err)
					return
				}
				observer.send(value: response?.httpResponse?.statusCode ?? 200 < 300)
			}
		}
	}

	/// creates a request from parameters
	///
	/// - Parameters:
	///   - url: the url to request
	///   - lastModified: the date to use for if-modified-since
	///   - etag: the etag to use
	/// - Returns: a request with the specified parameters
	private func request(url: URL, lastModified: Date?, etag: String?) -> URLRequest {
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
		if let theEtag = etag {
			request.addValue(theEtag, forHTTPHeaderField: "ETag")
		}
		if let lastMod = lastModified {
			request.addValue(URLStateChecker.lastModFormatter.string(from: lastMod), forHTTPHeaderField: "If-Modified-Since")
		}
		return request
	}
}
