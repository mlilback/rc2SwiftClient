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

public extension DefaultsKeys {
	public static let openSessions = DefaultsKey<JSON?>("OpenSessions")
	public static let maxCommandHistory = DefaultsKey<Int>("MaxCommandHistorySize")
	//import
	public static let lastImportDirectory = DefaultsKey<Data?>("rc2.LastImportDirectory")
	public static let replaceFiles = DefaultsKey<Bool>("rc2.ImportReplacesExistingFiles")

	public static let autosaveEnabled = DefaultsKey<Bool>("AutoSaveEnabled")
	public static let wordWrapEnabled = DefaultsKey<Bool>("WordWrapEnabled")
	public static let openGeneratedFiles = DefaultsKey<Bool>("OpenGeneratedFiles")
	
	public static let lastExportDirectory = DefaultsKey<Data?>("rc2.LastExportDirectory")

	public static let helpTopicSearchSummaries = DefaultsKey<Bool>("rc2.helpSidebar.searchSummaries")
	
	public static let editorFont = DefaultsKey<FontDescriptor?>("rc2.editor.font")
	public static let defaultFontSize = DefaultsKey<CGFloat>("rc2.defaultFontSize")
	public static let consoleOutputFont = DefaultsKey<FontDescriptor?>("rc2.console.font")
	public static let clearImagesWithConsole = DefaultsKey<Bool>("clearImagesWithConsole")
	
	public static let inNotebookView = DefaultsKey<Bool>("editorInNotebookView")
	public static let suppressDeleteTemplate = DefaultsKey<Bool>("suppressDeleteTemplate")
	public static let suppressDeleteFileWarnings = DefaultsKey<Bool>("SuppressDeleteFileWarning")
	public static let suppressClearWorkspace = DefaultsKey<Bool>("SuppressClearWorkspaceWarning")
	public static let suppressClearImagesWithConsole = DefaultsKey<Bool>("SuppressClearImagesWithConsole")
	public static let suppressDeleteChunkWarnings = DefaultsKey<Bool>("SuppressDeleteChunkWarning")
	public static let suppressKeys = [suppressDeleteFileWarnings, suppressClearWorkspace, suppressClearImagesWithConsole, suppressDeleteTemplate, .suppressDeleteChunkWarnings]
}
