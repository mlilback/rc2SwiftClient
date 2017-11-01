//
//  PreferenceKeys.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import SwiftyUserDefaults
import Freddy
import Networking

extension DefaultsKeys {
	static let openSessions = DefaultsKey<JSON?>("OpenSessions")
	static let maxCommandHistory = DefaultsKey<Int>("MaxCommandHistorySize")
	//import
	static let lastImportDirectory = DefaultsKey<Data?>("rc2.LastImportDirectory")
	static let replaceFiles = DefaultsKey<Bool>("rc2.ImportReplacesExistingFiles")

	static let wordWrapEnabled = DefaultsKey<Bool>("WordWrapEnabled")
	
	static let lastExportDirectory = DefaultsKey<Data?>("rc2.LastExportDirectory")

	static let helpTopicSearchSummaries = DefaultsKey<Bool>("rc2.helpSidebar.searchSummaries")
	
	static let defaultFontSize = DefaultsKey<CGFloat>("rc2.defaultFontSize")
	static let consoleOutputFont = DefaultsKey<FontDescriptor?>("rc2.console.font")
	static let clearImagesWithConsole = DefaultsKey<Bool>("clearImagesWithConsole")
	
	static let suppressDeleteFileWarnings = DefaultsKey<Bool>("SuppressDeleteFileWarning")
	static let suppressClearWorkspace = DefaultsKey<Bool>("SuppressClearWorkspaceWarning")
	static let suppressClearImagesWithConsole = DefaultsKey<Bool>("SuppressClearImagesWithConsole")
	static let suppressKeys = [suppressDeleteFileWarnings, suppressClearWorkspace, suppressClearImagesWithConsole]
}
