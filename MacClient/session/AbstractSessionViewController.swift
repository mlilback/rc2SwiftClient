//
//  AbstractSessionViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import SwiftyUserDefaults

class AbstractSessionViewController: NSViewController {
	weak var sessionOptional: Session? { didSet { sessionChanged() } }
	///convience accessor so don't have to constantly unwrap optional
	var session: Session { return sessionOptional! }
	//injected on load
	weak var appStatus: MacAppStatus? { didSet {
		appStatusChanged()
	} }
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
	}
	
	///for subclasses
	func sessionChanged() {
	}
	
	func appStatusChanged() {
	}
	
	/// Displays an alert sheet to confirm an action
	///
	/// - Parameters:
	///   - message: The message to display
	///   - infoText: The informative text to display
	///   - buttonTitle: The title for the rightmost/action button
	///   - defaultToCancel: true if the cancel button should be the default button. defaults to false
	///   - suppressionKey: Optional UserDefaults key to set to true if user selects to suppress future alerts. If nil, suppression checkbox is not displayed. Defaults to nil
	///   - handler: called after the user has selected an action
	///   - confirmed: true if the user selected the action button
	func confirmAction(message: String, infoText: String, buttonTitle: String, cancelTitle: String = NSLocalizedString("Cancel", comment: ""), defaultToCancel: Bool = false, suppressionKey: DefaultsKey<Bool>? = nil, handler: @escaping (_ confirmed: Bool) -> Void)
	{
		let alert = NSAlert()
		alert.showsSuppressionButton = suppressionKey != nil
		alert.messageText = message
		alert.informativeText = infoText
		alert.addButton(withTitle: buttonTitle)
		alert.addButton(withTitle: cancelTitle)
		if defaultToCancel {
			alert.buttons[0].keyEquivalent = ""
			alert.buttons[1].keyEquivalent = "\r"
		}
		alert.beginSheetModal(for: self.view.window!, completionHandler: { [weak alert] response in
			if let key = suppressionKey, alert?.suppressionButton?.state ?? .off == .on {
				UserDefaults.standard[key] = true
			}
			handler(response == .alertFirstButtonReturn)
		})
	}
}

func firstChildViewController<T>(_ rootController: NSViewController) -> T? {
	return firstRecursiveDescendent(rootController,
		children: { return $0.childViewControllers },
		filter: { return $0 is T }) as? T
}
