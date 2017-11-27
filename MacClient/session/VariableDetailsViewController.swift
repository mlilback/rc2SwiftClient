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
	static let spreadSheet = NSUserInterfaceItemIdentifier(rawValue: "spreadsheet")
}

class VariableDetailsViewController: NSViewController {
	private var variable: Variable?
	@IBOutlet var nameField: NSTextField!
	@IBOutlet var detailsField: NSTextField!
	var tabController: VariableDetailsTabViewController?
	var tabView: NSTabView?
	var simpleListController: ValuesVariableDetailController?
	var textDetailsController: TextVariableDetailController?
	var ssheetController: SpreadsheetVariableDetailController?
	var identifiers = [NSUserInterfaceItemIdentifier: NSTabViewItem]()
	var formatter: VariableFormatter?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		nameField.stringValue = ""
		detailsField.stringValue = ""
		let doubleFmt = NumberFormatter()
		doubleFmt.numberStyle = .decimal
		doubleFmt.minimumIntegerDigits = 1
		let dateFmt = DateFormatter()
		dateFmt.locale = Locale(identifier: "en_US_POSIX")
		dateFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
		formatter = VariableFormatter(doubleFormatter: doubleFmt, dateFormatter: dateFmt)
	}
	
	/// loads the appropriate viewcontroller and displays the variable
	///
	/// - Parameter variable: The variable to display
	/// - Returns: the suggested size necessary to display the variable
	func display(variable: Variable) -> NSSize {
		guard nameField != nil else { fatalError("display(variable:) called before view loaded") }
		self.variable = variable
		nameField.stringValue = variable.name
		detailsField.stringValue = variable.description
		if let values = formatter?.formatValues(for: variable) {
			tabView?.selectTabViewItem(withIdentifier: NSUserInterfaceItemIdentifier.simpleList)
			simpleListController?.set(variable: variable, values: values)
			print("simple list")
			return NSSize(width: 100, height: 200)
		} else if let matrixData = variable.matrixData, let values = formatter?.formatValues(for: matrixData.value) {
			tabView?.selectTabViewItem(withIdentifier: NSUserInterfaceItemIdentifier.spreadSheet)
			let ssource = MatrixDataSource(variable: variable, data: matrixData, values: values)
			_ = ssheetController!.set(variable: variable, source: ssource)
			let idealWidth = 40 + (matrixData.colCount * 50)
			let idealHeight = 80 + (matrixData.rowCount * 32)
			let sz = NSSize(width: min(max(idealWidth, 400), 200), height: min(max(idealHeight, 400), 200))
			print("matrix \(idealWidth) x \(idealHeight), actual = \(sz)")
			return sz
		} else if let dataframeData = variable.dataFrameData, let formatter = formatter {
			tabView?.selectTabViewItem(withIdentifier: NSUserInterfaceItemIdentifier.spreadSheet)
			let ssource = DataFrameDataSource(variable: variable, data: dataframeData, formatter: formatter)
			let sz = ssheetController!.set(variable: variable, source: ssource)
			return sz
		} else {
			// if nothing else, show description in text view
			tabView?.selectTabViewItem(withIdentifier: NSUserInterfaceItemIdentifier.textDetails)
			textDetailsController?.textView.string = variable.summary
		}
		return NSSize(width: 300, height: 200)
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
				simpleController.view.isHidden = false // force the view/controller to load
			} else if let textController = item.viewController as? TextVariableDetailController {
				textDetailsController = textController
				textController.identifier = .textDetails
				identifiers[.textDetails] = item
				textController.view.isHidden = false // force the view/controller to load
			} else if let sheetController = item.viewController as? SpreadsheetVariableDetailController {
				ssheetController = sheetController
				sheetController.identifier = .spreadSheet
				identifiers[.spreadSheet] = item
				ssheetController?.view.isHidden = false // force the view/controller to load
			}
		}
	}
}


class VariableDetailsTabViewController: NSTabViewController {
}

