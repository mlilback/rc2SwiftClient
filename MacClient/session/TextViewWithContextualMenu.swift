//
//  TextViewWithContextualMenu.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import AppKit
import os

class TextViewWithContextualMenu: NSTextView {
	
	override func awakeFromNib() {
		super.awakeFromNib()
		usesFindBar = true
	}
	
	override func menu(for event: NSEvent) -> NSMenu? {
		let defaultMenu = super.menu(for: event)
		let menu = NSMenu(title: "")
		for anItem in (defaultMenu?.items)! {
			os_log("context item %@ = %@.%@ (%@)", type:.info, anItem.title, anItem.target as! NSObject, anItem.action?.description ?? "<noaction>", anItem.tag)
		}
		//copy look up xxx and search with Google menu items
		if let lookupItem = defaultMenu?.items.filter({ $0.title.hasPrefix("Look Up") }).first {
			menu.addItem(lookupItem.copy() as! NSMenuItem)
			if let searchItem = defaultMenu?.items.filter({ $0.title.hasPrefix("Search with") }).first {
				menu.addItem(searchItem.copy() as! NSMenuItem)
			}
			menu.addItem(NSMenuItem.separator())
		}
		let preEditCount = menu.items.count
		//add the cut/copy/paste menu items
		if self.isEditable, let item = defaultMenu?.itemWithAction(#selector(NSText.cut(_:)), recursive: false) {
			menu.addItem(item.copy() as! NSMenuItem)
		}
		if let item = defaultMenu?.itemWithAction(#selector(NSText.copy(_:)), recursive: false) {
			menu.addItem(item.copy() as! NSMenuItem)
		}
		if let item = defaultMenu?.itemWithAction(#selector(NSText.paste(_:)), recursive: false) {
			menu.addItem(item.copy() as! NSMenuItem)
		}
		if menu.items.count > preEditCount {
			menu.addItem(NSMenuItem.separator())
		}
		//add our font and size menus
		if let fontItem = NSApp.mainMenu?.itemWithAction(#selector(ManageFontMenu.showFonts(_:)), recursive: true) {
			menu.addItem(fontItem.copy() as! NSMenuItem)
		}
		if let sizeItem = NSApp.mainMenu?.itemWithAction(#selector(ManageFontMenu.showFontSizes(_:)), recursive: true) {
			sizeItem.title = NSLocalizedString("Font Size", comment: "")
			menu.addItem(sizeItem.copy() as! NSMenuItem)
		}
		//add speak menu if there
		if let speak = defaultMenu?.itemWithAction(#selector(NSTextView.startSpeaking(_:)), recursive: true) {
			menu.addItem(NSMenuItem.separator())
			menu.addItem(speak.parent!.copy() as! NSMenuItem)
		}
		return menu
	}
}
