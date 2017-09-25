//
//  LoginFactory.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import os
import ReactiveSwift
import Model

fileprivate let maxRetries = 4

/// Factory class used to login and return a ConnectionInfo for that connection
// must subclass NSObject to be a delegate to URLSession api
public final class LoginFactory: NSObject {
	// MARK: - properties
	let sessionConfig: URLSessionConfiguration
	fileprivate var urlSession: URLSession?
	fileprivate var requestUrl: URL!
	fileprivate var requestData: Data!
	fileprivate var loginResponse: URLResponse?
	fileprivate var responseData: Data
	fileprivate var host: ServerHost?
	fileprivate var task: URLSessionDataTask?
	fileprivate var retryCount: Int = 0
	
	// MARK: - methods
	
	/// factory object to perform a login
	///
	/// - Parameter config: should include any necessary headers such as User-Agent
	public required init(config: URLSessionConfiguration = .default) {
		self.sessionConfig = config
		responseData = Data()
		super.init()
		urlSession = URLSession(configuration: sessionConfig)
	}
	
	/// returns a SignalProducer to start the login process
	///
	/// - Parameters:
	///   - destHost: the host to connect to
	///   - login: the user's login name
	///   - password: the user's password
	/// - Returns: a signal producer that returns the ConnectionInfo or an Error
	public func login(to destHost: ServerHost, as login: String, password: String) -> SignalProducer<ConnectionInfo, Rc2Error>
	{
		assert(urlSession != nil, "login can only be called once")
		host = destHost
		var reqdata: Data!
		do {
			reqdata = try JSONEncoder().encode(LoginData(login: login, password: password))
		} catch {
			os_log("json serialization of login info failed", log: .network, type: .error)
			fatalError()
		}
		requestUrl = URL(string: "login", relativeTo: destHost.url!)!
		return urlSession!.getData(request: loginRequest(requestUrl: requestUrl, data: reqdata))
			.retry(upTo: maxRetries, interval: 3.0, on: QueueScheduler.main)
			.map { data -> LoginResponse? in
				guard let rsp = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
					os_log("invalid json data from login", log: .network, type: .error)
					return nil
				}
				return rsp
			}
			.flatMap(.concat, getUserInfo)
			.on(terminated: { self.urlSession = nil })
	}
	
	private func getUserInfo(loginInfo: LoginResponse?) -> SignalProducer<ConnectionInfo, Rc2Error> {
		assert(urlSession != nil, "login can only be called once")
		guard let loginInfo = loginInfo else {
			return SignalProducer<ConnectionInfo, Rc2Error>(error: Rc2Error(type: .network, explanation: "failed to get login info."))
		}
		var request = URLRequest(url: URL(string: "info", relativeTo: host!.url!)!)
		request.addValue("application/json", forHTTPHeaderField: "Accept")
		request.addValue("Bearer \(loginInfo.token)", forHTTPHeaderField: "Authorization")
		return urlSession!.getData(request: request)
			.map({ data -> (Data, String) in return (data, loginInfo.token) })
			.flatMap(.concat, createConnectionInfo)
	}
	
	private func createConnectionInfo(data: Data, token: String) -> SignalProducer<ConnectionInfo, Rc2Error> {
		return SignalProducer<ConnectionInfo, Rc2Error> { observer, _ in
			do {
				let cinfo = try ConnectionInfo(host: self.host!, bulkInfoData: data, authToken: token)
				observer.send(value: cinfo)
				observer.sendCompleted()
			} catch {
				observer.send(error: Rc2Error(type: .invalidJson, explanation: ("failed to create connection info")))
			}
		}
	}
	
	private func decodeJson<T: Decodable>(data: Data) -> SignalProducer<T, Rc2Error> {
		do {
			let obj = try JSONDecoder().decode(T.self, from: data)
			return SignalProducer<T, Rc2Error>(value: obj)
		} catch {
			return SignalProducer<T, Rc2Error>(error: Rc2Error(type: .invalidJson, nested: error))
		}
	}
	
	private func loginRequest(requestUrl: URL, data: Data) -> URLRequest {
		var request = URLRequest(url: requestUrl)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		request.addValue("application/json", forHTTPHeaderField: "Accept")
		request.httpBody = data
		return request
	}
	
	private struct LoginData: Encodable {
		var login: String
		var password: String
	}
	
	private struct LoginResponse: Decodable {
		var token: String
	}
}
