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
	@objc dynamic var consoleInputText = "" { didSet { canExecute = consoleInputText.characters.count > 0 } }
	@objc dynamic var canExecute = false
	var viewFileOrImage: ((_ fileWrapper: FileWrapper) -> Void)?
	var currentFontDescriptor: NSFontDescriptor {
		didSet {
			if let font = NSFont(descriptor: currentFontDescriptor, size: currentFontDescriptor.pointSize) {
				outputFont = font
				resultsView?.font = font
			}
		}
	}
	
	required init?(coder: NSCoder) {
		cmdHistory = CommandHistory(target:nil, selector:#selector(ConsoleOutputController.displayHistoryItem(_:)))
		// set a default font since required at init. will be changed in viewDidLoad() and restoreSessionState()
		currentFontDescriptor = NSFont.userFixedPitchFont(ofSize: 14.0)!.fontDescriptor
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
		restoreFont()
		//try switching to Menlo instead of default monospaced font
		ThemeManager.shared.activeOutputTheme.signal.observeValues { [weak self] _ in
			self?.themeChanged()
		}
	}
	
	// MARK: internal
	private func restoreFont() {
		var fdesc: FontDescriptor? = UserDefaults.standard[.consoleOutputFont]
		//pick a default font
		if fdesc == nil {
			fdesc = NSFontDescriptor(name: "Menlo-Regular", size: 14.0)
			UserDefaults.standard[.consoleOutputFont] = fdesc
		}
		var font = NSFont(descriptor: fdesc!, size: fdesc!.pointSize)
		if font == nil {
			font = NSFont.userFixedPitchFont(ofSize: 14.0)!
			fdesc = font!.fontDescriptor
		}
		currentFontDescriptor = fdesc!
	}

	func themeChanged() {
		let theme = ThemeManager.shared.activeOutputTheme.value
		let fullRange = resultsView!.textStorage!.string.fullNSRange
		let fontAttrs: [NSAttributedStringKey: Any] = [.font: outputFont, .foregroundColor: theme.color(for: .text)]
		resultsView?.textStorage?.addAttributes(fontAttrs, range: fullRange)
		theme.update(attributedString: resultsView!.textStorage!)
		resultsView?.backgroundColor = theme.color(for: .background)
	}
	
	//stores all custom attributes in the results view for later restoration
	func serializeCustomAttributes() -> JSON {
		var attributes: [JSON] = []
		let astr = resultsView!.textStorage!
		astr.enumerateAttributes(in: astr.string.fullNSRange, options: []) { (attrs, range, _) in
			if let aThemeAttr = attrs[OutputTheme.AttributeName] as? OutputThemeProperty {
				attributes.append(SavedOutputThemeAttribute(aThemeAttr, range: range).toJSON())
			}
		}
		// swiftlint:disable:next force_try (we created it and know it will work)
		return .array(attributes)
	}
	
	//deserializes custom attributes and applies to results view
	func applyCustomAttributes(json: JSON) {
		let ts = resultsView!.textStorage!
		guard let attrs: [SavedOutputThemeAttribute] = try? json.decodedArray() else { return }
		for anAttribute in attrs {
			ts.addAttribute(OutputTheme.AttributeName, value: anAttribute.property, range: anAttribute.range)
		}
	}
	
	fileprivate func actuallyClearConsole() {
		resultsView?.textStorage?.deleteCharacters(in: NSRange(location: 0, length: (resultsView?.textStorage?.length)!))
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
		mutStr.addAttributes([.font: outputFont], range: NSRange(location: 0, length: mutStr.length))
		resultsView!.textStorage?.append(mutStr)
		resultsView!.scrollToEndOfDocument(nil)
	}
	
	func saveSessionState() -> JSON {
		var dict = [String: JSON]()
		dict[SessionStateKey.History.rawValue] = cmdHistory.commands.toJSON()
		let fullRange = resultsView!.textStorage!.string.fullNSRange
		if let rtfd = resultsView?.textStorage?.rtfd(from: fullRange, documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd])
		{
			_ = try? rtfd.write(to: URL(fileURLWithPath: "/tmp/lastSession.rtfd"))
			dict[SessionStateKey.Results.rawValue] = .string(rtfd.base64EncodedString())
		}
		dict["attrs"] = serializeCustomAttributes()
		return .dictionary(dict)
	}

	func restoreSessionState(_ state: JSON) {
		if let commands: [String] = try? state.decodedArray(at: SessionStateKey.History.rawValue) {
			cmdHistory.commands = commands
		}
		guard let dataStr = try? state.getString(at: SessionStateKey.Results.rawValue), let data = Data(base64Encoded: dataStr) else { return }
		let ts = resultsView!.textStorage!
		//for some reason, NSLayoutManager is initially making the line with an attachment 32 tall, even though image is 48. On window resize, it corrects itself. so we are going to keep an array of attachment indexes so we can fix this later
		var fileIndexes: [Int] = []
		resultsView!.replaceCharacters(in: NSRange(location: 0, length: ts.length), withRTFD:data)
		if let attrs = state["attrs"] {
			applyCustomAttributes(json: attrs)
			themeChanged()
		}
		resultsView!.textStorage?.enumerateAttribute(.attachment, in: ts.string.fullNSRange, options: [], using:
		{ (value, range, _) -> Void in
			guard let attach = value as? NSTextAttachment else { return }
			let fw = attach.fileWrapper
			let fname = (fw?.filename!)!
			if fname.hasPrefix("img") {
				let cell = NSTextAttachmentCell(imageCell: #imageLiteral(resourceName: "graph"))
				cell.image?.size = ConsoleAttachmentImageSize
				ts.removeAttribute(.attachment, range: range)
				attach.attachmentCell = cell
				ts.addAttribute(.attachment, value: attach, range: range)
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
		ThemeManager.shared.activeOutputTheme.value.update(attributedString: ts)
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
		let defaults = UserDefaults.standard
		guard !defaults[.suppressClearImagesWithConsole] else {
			actuallyClearConsole()
			if defaults[.clearImagesWithConsole] { session.imageCache.clearCache() }
			return
		}
		confirmAction(message: NSLocalizedString("ClearConsoleWarning", comment: ""),
		              infoText: NSLocalizedString("ClearConsoleInfo", comment: ""),
		              buttonTitle: NSLocalizedString("ClearImagesButton", comment: ""),
		              cancelTitle: NSLocalizedString("ClearConsoleOnlyButton", comment: ""),
		              defaultToCancel: !defaults[.clearImagesWithConsole],
		              suppressionKey: .suppressClearImagesWithConsole)
		{ (clearImages) in
			defaults[.clearImagesWithConsole] = clearImages
			self.actuallyClearConsole()
			if clearImages { self.session.imageCache.clearCache() }
		}
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
	func performFind(action: NSTextFinder.Action) {
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
