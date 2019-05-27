//
//  PreferenceKeys.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Foundation
import SwiftyUserDefaults
import Freddy
import Networking

extension ServerHost: DefaultsSerializable {}

public extension DefaultsKeys {
	public static let currentCloudHost = DefaultsKey<ServerHost?>("currentCloudHost")
	
	public static let maxCommandHistory = DefaultsKey<Int>("MaxCommandHistorySize", defaultValue: 10)
	//import
	public static let lastImportDirectory = DefaultsKey<Data?>("rc2.LastImportDirectory")
	public static let replaceFiles = DefaultsKey<Bool>("rc2.ImportReplacesExistingFiles", defaultValue: false)

	public static let autosaveEnabled = DefaultsKey<Bool>("AutoSaveEnabled", defaultValue: false)
	public static let wordWrapEnabled = DefaultsKey<Bool>("WordWrapEnabled", defaultValue: false)
	public static let openGeneratedFiles = DefaultsKey<Bool>("OpenGeneratedFiles", defaultValue: false)
	
	public static let lastExportDirectory = DefaultsKey<Data?>("rc2.LastExportDirectory")

	public static let helpTopicSearchSummaries = DefaultsKey<Bool>("rc2.helpSidebar.searchSummaries", defaultValue: false)
	
	public static let editorFont = DefaultsKey<FontDescriptor?>("rc2.editor.font")
	public static let defaultFontSize = DefaultsKey<Double>("rc2.defaultFontSize", defaultValue: 14.0)
	public static let consoleOutputFont = DefaultsKey<FontDescriptor?>("rc2.console.font")
	public static let clearImagesWithConsole = DefaultsKey<Bool>("clearImagesWithConsole", defaultValue: false)
	
	public static let inNotebookView = DefaultsKey<Bool>("editorInNotebookView", defaultValue: false)
	public static let suppressDeleteTemplate = DefaultsKey<Bool>("suppressDeleteTemplate", defaultValue: false)
	public static let suppressDeleteFileWarnings = DefaultsKey<Bool>("SuppressDeleteFileWarning", defaultValue: false)
	public static let suppressClearWorkspace = DefaultsKey<Bool>("SuppressClearWorkspaceWarning", defaultValue: false)
	public static let suppressClearImagesWithConsole = DefaultsKey<Bool>("SuppressClearImagesWithConsole", defaultValue: false)
	public static let suppressDeleteChunkWarnings = DefaultsKey<Bool>("SuppressDeleteChunkWarning", defaultValue: false)
	public static let suppressKeys = [suppressDeleteFileWarnings, suppressClearWorkspace, suppressClearImagesWithConsole, suppressDeleteTemplate, .suppressDeleteChunkWarnings]
}
