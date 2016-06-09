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

let RestLoginChangedNotification = "RestLoginChangedNotification"
let SelectedWorkspaceChangedNotification = "SelectedWorkspaceChangedNotification"
let CurrentSessionChangedNotification = "CurrentSessionChangedNotification"
///The object can be either a HelpTopic or a String
let DisplayHelpTopicNotification = "DisplayHelpTopicNotification"

///will always be posted on the main thread
let AppStatusChangedNotification = "AppStatusChangedNotification"

let PrefMaxCommandHistory = "MaxCommandHistorySize"
let PrefWordWrap = "WordWrapEnabled"
let OutputColorsKey = "OutputColors"

let ConsoleAttachmentImageSize = CGSize(width: 48, height: 48)

let HelpUrlBase = "http://stat.wvu.edu/rc2/library"
let HelpUrlFuncSeperator = "/html"

let VariableUpdatedBackgroundColor = PlatformColor.greenColor()
let VariableNormalBackgroundColor = PlatformColor.whiteColor()
