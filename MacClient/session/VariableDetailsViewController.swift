//
//  VariableDetailsViewController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

fileprivate extension NSUserInterfaceItemIdentifier {
	static let simpleList = NSUserInterfaceItemIdentifier(rawValue: "simpleList")
	static let textDetails = NSUserInterfaceItemIdentifier(rawValue: "textDetails")
}

class VariableDetailsViewController: NSViewController {
	private var variable: Variable?
	@IBOutlet var nameField: NSTextField!
	@IBOutlet var detailsField: NSTextField!
	var tabController: VariableDetailsTabViewController?
	var tabView: NSTabView?
	var simpleListController: ValuesVariableDetailController?
	var textDetailsController: TextVariableDetailController?
	var identifiers = [NSUserInterfaceItemIdentifier: NSTabViewItem]()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		nameField.stringValue = ""
		detailsField.stringValue = ""
	}
	
	func display(variable: Variable) {
		guard nameField != nil else { fatalError("display(variable:) called before view loaded") }
		self.variable = variable
		nameField.stringValue = variable.name
		detailsField.stringValue = variable.description
		if variable.isPrimitive {
			tabView?.selectTabViewItem(withIdentifier: NSUserInterfaceItemIdentifier.simpleList)
			simpleListController?.variable = variable
		} else {
			tabView?.selectTabViewItem(withIdentifier: NSUserInterfaceItemIdentifier.textDetails)
			textDetailsController?.textView.string = variable.summary
		}
	}
	
	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		guard let tabController = segue.destinationController as? NSTabViewController else { return }
		self.tabController = tabController as? VariableDetailsTabViewController
		tabView = tabController.tabView
		for item in tabController.tabViewItems {
			if let simpleController = item.viewController as? ValuesVariableDetailController {
				simpleListController = simpleController
				simpleController.identifier = .simpleList
				identifiers[.simpleList] = item
			} else if let textController = item.viewController as? TextVariableDetailController {
				textDetailsController = textController
				textController.identifier = .textDetails
				identifiers[.textDetails] = item
			}
		}
	}
}


class VariableDetailsTabViewController: NSTabViewController {
}

