//
//  Constants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore

let Rc2ErrorDomain = "Rc2ErrorDomain"

public struct Notifications {
	///will always be posted on the main thread
	static let AppStatusChanged = "AppStatusChangedNotification"
	///The object can be either a HelpTopic or a String
	static let DisplayHelpTopic = "DisplayHelpTopicNotification"
}

struct LStrings {
	static let DeleteFileWarning = "DeleteFileWarning"
	static let DeleteFileWarningInfo = "DeleteFileWarningInfo"
}

struct Constants {
	static let DefaultProjectName = "default"
	static let DefaultWorkspaceName = "default"
	static let DefaultBookmarkName = "local"
	static let LocalBookmarkGroupName = NSLocalizedString("Local Server", comment: "")
	static let LocalServerPassword = "local"
}

let ConsoleAttachmentImageSize = CGSize(width: 48, height: 48)

let HelpUrlBase = "http://www.rc2.io/help/library"
let HelpUrlFuncSeperator = "/html"

let VariableUpdatedBackgroundColor = PlatformColor.green
let VariableNormalBackgroundColor = PlatformColor.white
