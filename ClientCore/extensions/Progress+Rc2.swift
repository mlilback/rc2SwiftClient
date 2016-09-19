//
//  Progress+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import PMKVObserver

///Keys used by this extention of Progress
public extension ProgressUserInfoKey {
	public static let rc2ErrorKey = ProgressUserInfoKey("rc2.error")
	public static let rc2HandlerKey = ProgressUserInfoKey("rc2.handlers")
}

///an alias to a completion handler
public typealias ProgressCompletionHandler = (Progress, NSError?) -> Void

///internal object used to store additional info about a Progress via userInfo
struct ProgressProxy {
	var handlers:[ProgressCompletionHandler] = []
	var completed:Bool = false
	func executeHandlers(progress: Progress, error:NSError?) {
		DispatchQueue.main.async {
			for (_,block) in self.handlers.enumerated() {
				block(progress, error)
			}
		}
	}
}

public extension Progress {
	///The error that is related to this Progress
	public var rc2Error: NSError? {
		get { return self.userInfo[.rc2ErrorKey] as? NSError }
		set { self.setUserInfoObject(newValue, forKey: .rc2ErrorKey) }
	}
	
	///Marks the Progress as complete and calls all registered callback handlers
	/// - parameter withError: optional error if progress action failed
	public func complete(withError error:NSError?) {
		rc2Error = error
		guard var proxy = self.userInfo[.rc2HandlerKey] as? ProgressProxy else {  return }
		proxy.completed = true
		proxy.executeHandlers(progress: self, error: error)
		setUserInfoObject(proxy, forKey: .rc2HandlerKey)
	}
	
	///adds a completion handler. If already complete, the handler will be called on the main queue synchronously
	public func addCompletionHandler(handler:@escaping ProgressCompletionHandler) {
		if var proxy = self.userInfo[.rc2HandlerKey] as? ProgressProxy {
			//if already completed, execute immediately
			if proxy.completed {
				DispatchQueue.main.sync {
					handler(self, self.rc2Error)
				}
			} else {
				//add to handlers
				proxy.handlers.append(handler)
				self.setUserInfoObject(proxy, forKey: .rc2HandlerKey)
			}
		} else {
			//create proxy and add handler
			var proxy = ProgressProxy()
			proxy.handlers.append(handler)
			self.setUserInfoObject(proxy, forKey: .rc2HandlerKey)
		}
	}
}
