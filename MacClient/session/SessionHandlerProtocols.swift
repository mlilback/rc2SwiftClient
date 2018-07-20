//
//  SessionHandlerProtocols.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Model
import Networking
import ClientCore

///These protocols exist to decouple various view controllers

/// Abstracts the idea of processing variable messages
public protocol VariableHandler {
	/// a variable value has been received
	func variableUpdated(_ update: SessionResponse.VariableValueData)
	
	/// the server has returned a variable update
	func variablesUpdated(_ update: SessionResponse.ListVariablesData)
}

protocol SearchResponder: class {
	var searchBarVisible: Bool { get set }
	func performTextFinderAction(_ sender: Any?)
}

extension SearchResponder {
	func performTextFinderAction(_ sender: Any?) {}
}

protocol OutputHandler: SearchResponder {
	var sessionController: SessionController? { get set }
	func append(responseString: ResponseString)
	func save(state: inout SessionState.OutputControllerState)
	func restore(state: SessionState.OutputControllerState)
	func handleSearch(action: NSTextFinder.Action)
	func initialFirstResponder() -> NSResponder
	func show(file: AppFile?)
	func showHelp(_ topics: [HelpTopic])
	//action event forwarding
	func clearConsole(_ sender: AnyObject?)
	func toggleSearchBar()
}

/// Implemented by objects that need to response to changes related to files
protocol FileHandler: class {
	var selectedFile: AppFile? { get set }

	/// Updates data for file changes
	///
	/// - Parameter changes: the file changes
	func filesRefreshed(_ changes: [AppWorkspace.FileChange])

	/// prompts the user to import file(s)
	///
	/// - Parameter sender: the sender of the import. unused
	func promptToImportFiles(_ sender: Any?)

	/// action to edit the selected file (necessary for dual use files)
	///
	/// - Parameter sender: the sender of the action. unused
	func editFile(_ sender: Any)
	
	/// called to validate any menu items the FileHandler uses
	///
	/// - Parameter menuItem: the menu item to validate
	/// - Returns: true if the menu item was handled
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
}
