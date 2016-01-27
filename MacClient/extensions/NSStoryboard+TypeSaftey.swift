//
//  NSStoryboard+TypeSaftey.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

/**
	This code allows the following:

	let storyboard = NSStoryboard.storyboard(.MainWindow)
	let rootVC: RootViewController = storyboard.instantiateViewController()

	no more casting or string constants

	Based on this [article](https://medium.com/swift-programming/uistoryboard-safer-with-enums-protocol-extensions-and-generics-7aad3883b44d#.o6iarw92x)
*/
extension NSStoryboard {
	enum Storyboard: String {
		case Main
		case MainWindow
	}
	
	convenience init(storyboard: Storyboard, bundle:NSBundle? = nil) {
		self.init(name:storyboard.rawValue, bundle:bundle)
	}

	func instantiateViewController<T: NSViewController where T: StoryboardIdentifiable>() -> T {
		let optionalViewController = self.instantiateControllerWithIdentifier(T.storyboardIdentifier)
		
		guard let viewController = optionalViewController as? T  else {
			fatalError("Couldn’t instantiate view controller with identifier \(T.storyboardIdentifier)")
		}
		
		return viewController
	}

	func instantiateWindowController<T: NSWindowController where T: StoryboardIdentifiable>() -> T {
		let optionalController = self.instantiateControllerWithIdentifier(T.storyboardIdentifier)
		
		guard let controller = optionalController as? T  else {
			fatalError("Couldn’t instantiate window controller with identifier \(T.storyboardIdentifier)")
		}
		
		return controller
	}
}

protocol StoryboardIdentifiable {
	static var storyboardIdentifier: String { get }
}

extension StoryboardIdentifiable where Self: NSViewController {
	static var storyboardIdentifier: String {
		return String(self)
	}
}

extension StoryboardIdentifiable where Self: NSWindowController {
	static var storyboardIdentifier: String {
		return String(self)
	}
}

extension NSViewController: StoryboardIdentifiable { }

extension NSWindowController: StoryboardIdentifiable { }
