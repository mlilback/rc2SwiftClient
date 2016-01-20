//
//  NSToolbarItem+Validate.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa


private var valKey: UInt8 = 0
extension NSToolbarItem {
	typealias validateClosureType = (item:NSToolbarItem) -> (Void)
	class ValidateWrapper : NSObject {
		var closure: validateClosureType?
		init(closure:validateClosureType?) {
			self.closure = closure
		}
	}
	var validateClosure: validateClosureType? {
		get {
			let wrapper = objc_getAssociatedObject(self, &valKey) as? ValidateWrapper
			return wrapper?.closure
		}
		set {
			let wrapper = ValidateWrapper(closure: newValue)
			objc_setAssociatedObject(self, &valKey, wrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
	}
	
	override public class func initialize() {
		guard self == NSToolbarItem.self else {
			return
		}
		struct Once {
			static var once: dispatch_once_t = 0;
		}
		dispatch_once(&Once.once)
		{
			let baseSel = Selector("validate")
			let baseMethod = class_getInstanceMethod(self, baseSel)
			let newSel = Selector("myValidate")
			let originalValidate = class_getInstanceMethod(self, newSel)
			method_exchangeImplementations(baseMethod, originalValidate)
		}
	}
	
	dynamic func myValidate() {
		validateClosure?(item: self)
	}
}
