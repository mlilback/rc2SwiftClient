//
//  ConsoleOutputController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Cocoa
import Freddy
import Networking
import os

enum SessionStateKey: String {
	case History = "history"
	case Results = "results"
}

///ViewController whose view contains the text view showing the results, and the text field for entering short queries
class ConsoleOutputController: AbstractSessionViewController, OutputController, NSTextViewDelegate, NSTextFieldDelegate
{
	// MARK: properties
	@IBOutlet var resultsView: ResultsView?
	@IBOutlet var consoleTextField: ConsoleTextField?
	@IBOutlet var historyButton: NSSegmentedControl?
	var outputFont: NSFont = NSFont(name: "Menlo", size: 14)!
	let cmdHistory: CommandHistory
	dynamic var consoleInputText = "" { didSet { canExecute = consoleInputText.characters.count > 0 } }
	dynamic var canExecute = false
	var viewFileOrImage: ((_ fileWrapper: FileWrapper) -> Void)?
	var currentFontDescriptor: NSFontDescriptor = NSFont.userFixedPitchFont(ofSize: 14.0)!.fontDescriptor {
		didSet {
			let font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)
			resultsView?.font = font
		}
	}
	
	required init?(coder: NSCoder) {
		cmdHistory = CommandHistory(target:nil, selector:#selector(ConsoleOutputController.displayHistoryItem(_:)))
		super.init(coder: coder)
	}
	
	// MARK: overrides
	override func viewDidLoad() {
		super.viewDidLoad()
		cmdHistory.target = self
		consoleTextField?.adjustContextualMenu = { (editor: NSText, theMenu: NSMenu) in
			return theMenu
		}
		resultsView?.textContainerInset = NSSize(width: 4, height: 4)
		//try switching to Menlo instead of default monospaced font
		let fdesc = NSFontDescriptor(name: "Menlo-Regular", size: 14.0)
		if let _ = NSFont(descriptor: fdesc, size: fdesc.pointSize)
		{
			currentFontDescriptor = fdesc
		}
		NotificationCenter.default.addObserver(self, selector: #selector(themeChanged(_:)), name: .outputThemeChanged, object: nil)
	}
	
	// MARK: internal
	@objc func themeChanged(_ note: Notification?) {
		let font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize)!
		resultsView?.textStorage?.addAttribute(NSFontAttributeName, value: font, range: resultsView!.textStorage!.string.fullNSRange)
		let theme = UserDefaults.standard.activeOutputTheme
		theme.update(attributedString: resultsView!.textStorage!)
	}
	
	//stores all custom attributes in the results view for later restoration
	func serializeCustomAttributes() -> Data {
		var attributes: [JSON] = []
		let astr = resultsView!.textStorage!
		astr.enumerateAttributes(in: astr.string.fullNSRange, options: []) { (attrs, range, _) in
			if let aThemeAttr = attrs[OutputTheme.AttributeName] as? OutputThemeProperty {
				attributes.append(SavedOutputThemeAttribute(aThemeAttr, range: range).toJSON())
			}
		}
		// swiftlint:disable:next force_try (we created it and know it will work)
		return try! JSON.array(attributes).serialize()
	}
	
	//deserializes custom attributes and applies to results view
	func applyCustomAttributes(data: Data) {
		let ts = resultsView!.textStorage!
		guard let json = try? JSON(data: data),
			let attrs: [SavedOutputThemeAttribute] = try? json.decodedArray()
			else { return }
		for anAttribute in attrs {
			ts.addAttribute(OutputTheme.AttributeName, value: anAttribute.property, range: anAttribute.range)
		}
	}
	
	// MARK: actions
	@IBAction func executeQuery(_ sender: AnyObject?) {
		guard consoleInputText.characters.count > 0 else { return }
		session.executeScript(consoleInputText)
		cmdHistory.addToCommandHistory(consoleInputText)
		consoleTextField?.stringValue = ""
	}
	
	// MARK: SessionOutputHandler
	func append(responseString: ResponseString) {
		// swiftlint:disable:next force_cast
		let mutStr = responseString.string.mutableCopy() as! NSMutableAttributedString
		mutStr.addAttributes([NSFontAttributeName: outputFont], range: NSRange(location: 0, length: mutStr.length))
		resultsView!.textStorage?.append(mutStr)
		resultsView!.scrollToEndOfDocument(nil)
	}
	
	func saveSessionState() -> AnyObject {
		var dict = [String: AnyObject]()
		dict[SessionStateKey.History.rawValue] = cmdHistory.commands as AnyObject?
		let fullRange = resultsView!.textStorage!.string.fullNSRange
		let rtfd = resultsView?.textStorage?.rtfd(from: fullRange, documentAttributes: [NSDocumentTypeDocumentAttribute: NSRTFDTextDocumentType])
		_ = try? rtfd?.write(to: URL(fileURLWithPath: "/tmp/lastSession.rtfd"))
		dict[SessionStateKey.Results.rawValue] = rtfd as AnyObject?
		dict["attrs"] = serializeCustomAttributes() as AnyObject
		dict["font"] = NSKeyedArchiver.archivedData(withRootObject: currentFontDescriptor) as AnyObject?
		return dict as AnyObject
	}

	func restoreSessionState(_ state: [String: AnyObject]) {
		if state[SessionStateKey.History.rawValue] is NSArray,
			let commands = state[SessionStateKey.History.rawValue] as? [String]
		{
			cmdHistory.commands = commands
		}
		guard let data = state[SessionStateKey.Results.rawValue] as? Data else { return }
		let ts = resultsView!.textStorage!
		//for some reason, NSLayoutManager is initially making the line with an attachment 32 tall, even though image is 48. On window resize, it corrects itself. so we are going to keep an array of attachment indexes so we can fix this later
		var fileIndexes: [Int] = []
		resultsView!.replaceCharacters(in: NSRange(location: 0, length: ts.length), withRTFD:data)
		if let attrData = state["attrs"] as? Data {
			applyCustomAttributes(data: attrData)
			themeChanged(nil)
		}
		resultsView!.textStorage?.enumerateAttribute(NSAttachmentAttributeName, in: ts.string.fullNSRange, options: [], using:
		{ (value, range, _) -> Void in
			guard let attach = value as? NSTextAttachment else { return }
			let fw = attach.fileWrapper
			let fname = (fw?.filename!)!
			if fname.hasPrefix("img") {
				let cell = NSTextAttachmentCell(imageCell: NSImage(named: "graph"))
				cell.image?.size = ConsoleAttachmentImageSize
				ts.removeAttribute(NSAttachmentAttributeName, range: range)
				attach.attachmentCell = cell
				ts.addAttribute(NSAttachmentAttributeName, value: attach, range: range)
			} else {
				attach.attachmentCell = self.attachmentCellForAttachment(attach)
				fileIndexes.append(range.location)
			}
		})
		//now go through all lines with an attachment and insert a space, and then delete it. that forces a layout that uses the correct line height
		fileIndexes.forEach {
			ts.insert(NSAttributedString(string: " "), at: $0)
			ts.deleteCharacters(in: NSRange(location: $0, length: 1))
		}
		UserDefaults.standard.activeOutputTheme.update(attributedString: ts)
		if let fontData = state["font"] as? Data,
			let fontDesc = NSKeyedUnarchiver.unarchiveObject(with: fontData) as? NSFontDescriptor
		{
			currentFontDescriptor = fontDesc
		}
		//scroll to bottom
		resultsView?.moveToEndOfDocument(self)
	}
	
	func attachmentCellForAttachment(_ attachment: NSTextAttachment) -> NSTextAttachmentCell? {
		guard let attach = try? MacConsoleAttachment.from(data: attachment.fileWrapper!.regularFileContents!) else { return nil }
		assert(attach.type == .file)
		let fileType = FileType.fileType(withExtension: attach.fileExtension!)
		let img = fileType?.image()
		img?.size = ConsoleAttachmentImageSize
		return NSTextAttachmentCell(imageCell: img)
	}
	
	// MARK: command history
	@IBAction func historyClicked(_ sender: AnyObject?) {
		cmdHistory.adjustCommandHistoryMenu()
		let hframe = historyButton?.superview?.convert((historyButton?.frame)!, to: nil)
		let rect = view.window?.convertToScreen(hframe!)
		cmdHistory.historyMenu.popUp(positioning: nil, at: (rect?.origin)!, in: nil)
	}

	@IBAction func displayHistoryItem(_ sender: AnyObject?) {
		guard let mi = sender as? NSMenuItem, let historyString = mi.representedObject as? String else {
			os_log("displayHistoryItem only support from menu item", log: .app)
			return
		}
		consoleInputText = historyString
		canExecute = consoleInputText.characters.count > 0
		//the following shouldn't be necessary because they are bound. But sometimes the textfield value does not update
		consoleTextField?.stringValue = consoleInputText
		view.window?.makeFirstResponder(consoleTextField)
	}
	
	@IBAction func clearConsole(_ sender: AnyObject?) {
		resultsView?.textStorage?.deleteCharacters(in: NSRange(location: 0, length: (resultsView?.textStorage?.length)!))
	}
	
	// MARK: textfield delegate
	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(NSResponder.insertNewline(_:)) {
			executeQuery(control)
			return true
		}
		return false
	}
	
	// MARK: textview delegate
	func textView(_ textView: NSTextView, clickedOn cell: NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int)
	{
		let attach = cell.attachment
		guard let fw = attach?.fileWrapper else { return }
		viewFileOrImage?(fw)
	}
}

extension ConsoleOutputController: Searchable {
	func performFind(action: NSTextFinderAction) {
		let menuItem = NSMenuItem(title: "foo", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
		menuItem.tag = action.rawValue
		resultsView?.performFindPanelAction(menuItem)
	}
}

// MARK: UsesAdjustableFont
extension ConsoleOutputController: UsesAdjustableFont {
	
	func fontsEnabled() -> Bool {
		return true
	}
	
	func fontChanged(_ menuItem: NSMenuItem) {
		guard let newNameDesc = menuItem.representedObject as? NSFontDescriptor else { return }
		let newDesc = newNameDesc.withSize(currentFontDescriptor.pointSize)
		currentFontDescriptor = newDesc
		resultsView?.font = NSFont(descriptor: newDesc, size: newDesc.pointSize)
	}
}

struct SavedOutputThemeAttribute: JSONDecodable, JSONEncodable {
	let property: OutputThemeProperty
	let range: NSRange
	
	init(_ property: OutputThemeProperty, range: NSRange) {
		self.property = property
		self.range = range
	}
	
	init(json: JSON) throws {
		guard let prop = OutputThemeProperty(rawValue: try json.getString(at: "prop")) else {
			throw Rc2Error(type: .invalidJson, explanation: "bad data for SavedOutputThemeAttribute")
		}
		self.property = prop
		self.range = NSRangeFromString(try json.getString(at: "range"))
	}
	
	func toJSON() -> JSON {
		return .dictionary(["range": .string(NSStringFromRange(self.range)), "prop": .string(property.rawValue)])
	}
}
