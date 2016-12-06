//
//  MacAppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking
import ClientCore

class MacAppStatus: AppStatus {

	override func presentError(_ error: Rc2Error, session: AnyObject?) {
		let alert = NSAlert()
		alert.messageText = error.localizedDescription
		alert.informativeText = error.nestedError?.localizedDescription ?? ""
		alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
		alert.beginSheetModal(for: getWindow(session as? Session), completionHandler:nil)
	}
	
	override func presentAlert(_ session:AnyObject?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = details
		if buttons.count == 0 {
			alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
		} else {
			for aButton in buttons {
				alert.addButton(withTitle: aButton)
			}
		}
		alert.alertStyle = isCritical ? .critical : .warning
		alert.beginSheetModal(for: getWindow((session as! Session)), completionHandler: { (rsp) in
			guard buttons.count > 1 else { return }
			DispatchQueue.main.async {
				//convert rsp to an index to buttons
				handler?(rsp - NSAlertFirstButtonReturn)
			}
		}) 
	}
}
