//
//  PreferenceKeys.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Foundation
import SwiftyUserDefaults
import Networking

extension ServerHost: DefaultsSerializable {}

public extension DefaultsKeys {
	static let currentCloudHost = DefaultsKey<ServerHost?>("currentCloudHost")
	
	static let maxCommandHistory = DefaultsKey<Int>("MaxCommandHistorySize", defaultValue: 10)
	//import
	static let lastImportDirectory = DefaultsKey<Data?>("rc2.LastImportDirectory")
	static let replaceFiles = DefaultsKey<Bool>("rc2.ImportReplacesExistingFiles", defaultValue: false)

	static let autosaveEnabled = DefaultsKey<Bool>("AutoSaveEnabled", defaultValue: false)
	static let wordWrapEnabled = DefaultsKey<Bool>("WordWrapEnabled", defaultValue: false)
	static let openGeneratedFiles = DefaultsKey<Bool>("OpenGeneratedFiles", defaultValue: false)
	
	static let lastExportDirectory = DefaultsKey<Data?>("rc2.LastExportDirectory")

	static let helpTopicSearchSummaries = DefaultsKey<Bool>("rc2.helpSidebar.searchSummaries", defaultValue: false)
	
	static let editorFont = DefaultsKey<FontDescriptor?>("rc2.editor.font")
	static let defaultFontSize = DefaultsKey<Double>("rc2.defaultFontSize", defaultValue: 14.0)
	static let consoleOutputFont = DefaultsKey<FontDescriptor?>("rc2.console.font")
	static let clearImagesWithConsole = DefaultsKey<Bool>("clearImagesWithConsole", defaultValue: false)
	
	static let previewUpdateDelay = DefaultsKey<Double>("PreviewUpdateDelay", defaultValue: 0.5)

	static let suppressDeleteTemplate = DefaultsKey<Bool>("suppressDeleteTemplate", defaultValue: false)
	static let suppressDeleteFileWarnings = DefaultsKey<Bool>("SuppressDeleteFileWarning", defaultValue: false)
	static let suppressClearWorkspace = DefaultsKey<Bool>("SuppressClearWorkspaceWarning", defaultValue: false)
	static let suppressClearImagesWithConsole = DefaultsKey<Bool>("SuppressClearImagesWithConsole", defaultValue: false)
	static let suppressDeleteChunkWarnings = DefaultsKey<Bool>("SuppressDeleteChunkWarning", defaultValue: false)
	static let suppressKeys = [suppressDeleteFileWarnings, suppressClearWorkspace, suppressClearImagesWithConsole, suppressDeleteTemplate, .suppressDeleteChunkWarnings]
}
