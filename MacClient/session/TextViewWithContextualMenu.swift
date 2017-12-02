//
//  TextViewWithContextualMenu.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import AppKit

@objc protocol TextViewMenuDelegate: NSObjectProtocol {
	func additionalContextMenuItems() -> [NSMenuItem]?
}

///common base class for NSTextView that supports a customized contextual menu. Used for editor and console.
class TextViewWithContextualMenu: NSTextView {
	@IBOutlet weak var menuDelegate: TextViewMenuDelegate?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		usesFindBar = true
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		let defaultMenu = super.menu(for: event)
		let menu = NSMenu(title: "")
		//debugging code to show what items are in the default contextual menu
		//for anItem in (defaultMenu?.items)! {
		//	let targetd = (anItem.target as? NSObject)?.description ?? ""
		//	os_log("context item %{public}@ = %{public}@.%{public}@ (%{public}@)", log: .app, type: .info, anItem.title, targetd, anItem.action?.description ?? "<noaction>", anItem.tag)
		//}
		//add items for subclass
		if let otherItems = menuDelegate?.additionalContextMenuItems(), otherItems.count > 0 {
			otherItems.forEach { menu.addItem($0) }
			menu.addItem(NSMenuItem.separator())
		}
		//copy look up xxx and search with Google menu items
		if let lookupItem = defaultMenu?.items.first(where: { $0.title.hasPrefix("Look Up") }) {
			menu.addItem(copyMenuItem(lookupItem))
			if let searchItem = defaultMenu?.items.first(where: { $0.title.hasPrefix("Search with") }) {
				menu.addItem(copyMenuItem(searchItem))
			}
			menu.addItem(NSMenuItem.separator())
		}
		let preEditCount = menu.items.count
		//add the cut/copy/paste menu items
		if self.isEditable, let item = defaultMenu?.itemWithAction(#selector(NSText.cut(_:)), recursive: false) {
			menu.addItem(copyMenuItem(item))
		}
		if let item = defaultMenu?.itemWithAction(#selector(NSText.copy(_:)), recursive: false) {
			menu.addItem(copyMenuItem(item))
		}
		if let item = defaultMenu?.itemWithAction(#selector(NSText.paste(_:)), recursive: false) {
			menu.addItem(copyMenuItem(item))
		}
		if menu.items.count > preEditCount {
			menu.addItem(NSMenuItem.separator())
		}
		//add our font and size menus
		if let fontItem = NSApp.mainMenu?.itemWithAction(#selector(ManageFontMenu.showFonts(_:)), recursive: true) {
			menu.addItem(copyMenuItem(fontItem))
		}
		if let sizeItem = NSApp.mainMenu?.itemWithAction(#selector(ManageFontMenu.showFontSizes(_:)), recursive: true) {
			sizeItem.title = NSLocalizedString("Font Size", comment: "")
			menu.addItem(copyMenuItem(sizeItem))
		}
		//add speak menu if there
		if let speak = defaultMenu?.itemWithAction(#selector(NSTextView.startSpeaking(_:)), recursive: true) {
			menu.addItem(NSMenuItem.separator())
			menu.addItem(copyMenuItem(speak.parent!))
		}
		return menu
	}
	
	// only need to force_cast it once
	private func copyMenuItem(_ item: NSMenuItem) -> NSMenuItem {
		return item.copy() as! NSMenuItem // swiftlint:disable:this force_cast
	}
}
