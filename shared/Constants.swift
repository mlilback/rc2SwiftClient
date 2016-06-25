//
//  Constants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

let Rc2ErrorDomain = "Rc2ErrorDomain"

enum Rc2ErrorCode: Int {
	case ServerError = 101
}

struct Notifications {
	///will always be posted on the main thread
	static let AppStatusChanged = "AppStatusChangedNotification"
	///The object can be either a HelpTopic or a String
	static let DisplayHelpTopic = "DisplayHelpTopicNotification"
}



struct PrefKeys {
	static let LastWorkspace = "LastWorkspace"
	static let LocalServerWorkspaces = "LocalServerWorkspaces"
	static let LastHost = "LastHost"
	static let LastLogin = "LastLoginName"
	static let LastWasLocal = "LastWasLocal"
	
	static let MaxCommandHistorySize = "MaxCommandHistorySize"
	static let WordWrapEnabled = "WordWrapEnabled"
	static let OutputColors = "OutputColors"
}

let ConsoleAttachmentImageSize = CGSize(width: 48, height: 48)

let HelpUrlBase = "http://stat.wvu.edu/rc2/library"
let HelpUrlFuncSeperator = "/html"

let VariableUpdatedBackgroundColor = PlatformColor.greenColor()
let VariableNormalBackgroundColor = PlatformColor.whiteColor()
