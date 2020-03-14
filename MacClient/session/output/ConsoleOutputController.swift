//
//  ConsoleOutputController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Cocoa
import Networking
import MJLLogger
import Model
import ReactiveSwift

enum SessionStateKey: String {
	case History = "history"
	case Results = "results"
}

///ViewController whose view contains the text view showing the results, and the text field for entering short queries
class ConsoleOutputController: AbstractSessionViewController, OutputController, NSTextViewDelegate, NSTextFieldDelegate, TextViewMenuDelegate
{
	// MARK: - properties
	@IBOutlet var resultsView: ResultsView?
	@IBOutlet var consoleTextField: ConsoleTextField?
	@IBOutlet var historyButton: NSSegmentedControl?
	@IBOutlet var contextualMenuAdditions: NSMenu?

	weak var contextualMenuDelegate: ContextualMenuDelegate?
	
	var outputFont: NSFont = NSFont(name: "Menlo", size: 14)!
	let cmdHistory: CommandHistory
	@objc dynamic var consoleInputText = "" { didSet { canExecute = consoleInputText.count > 0 } }
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
	var supportsSearchBar: Bool { return true }
	var searchBarVisible: Bool { return resultsView?.enclosingScrollView?.isFindBarVisible ?? false }
	
	required init?(coder: NSCoder) {
		cmdHistory = CommandHistory(target:nil, selector:#selector(ConsoleOutputController.displayHistoryItem(_:)))
		// set a default font since required at init. will be changed in viewDidLoad() and restoreSessionState()
		currentFontDescriptor = NSFont.userFixedPitchFont(ofSize: 14.0)!.fontDescriptor
		super.init(coder: coder)
	}
	
	// MARK: - overrides
	override func viewDidLoad() {
		super.viewDidLoad()
		if #available(macOS 10.14, *) {
			resultsView?.appearance = NSAppearance(named: .aqua)
		}
		cmdHistory.target = self
		consoleTextField?.adjustContextualMenu = { (editor: NSText, theMenu: NSMenu) in
			return theMenu
		}
		resultsView?.menuDelegate = self
		resultsView?.textContainerInset = NSSize(width: 4, height: 4)
		restoreFont()
		//try switching to Menlo instead of default monospaced font
		ThemeManager.shared.activeOutputTheme.signal.observe(on: UIScheduler()).observeValues { [weak self] _ in
			self?.themeChanged()
		}
	}
	
	@objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action  {
		case #selector(ConsoleOutputController.clearConsole(_:)):
			return resultsView?.string.count ?? 0 > 0
		case #selector(ConsoleOutputController.historyClicked(_:)):
			return true
		case #selector(displayHistoryItem(_:)):
			return true
		default:
			return false
		}
	}
	
	// MARK: - internal
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
		let fontAttrs: [NSAttributedString.Key: Any] = [.font: outputFont, .foregroundColor: theme.color(for: .text)]
		resultsView?.textStorage?.addAttributes(fontAttrs, range: fullRange)
		theme.update(attributedString: resultsView!.textStorage!)
		resultsView?.backgroundColor = theme.color(for: .background)
	}
	
	fileprivate func actuallyClearConsole() {
		resultsView?.textStorage?.deleteCharacters(in: NSRange(location: 0, length: (resultsView?.textStorage?.length)!))
	}
	
	// MARK: - actions
	@IBAction func executeQuery(_ sender: Any?) {
		guard consoleInputText.count > 0 else { return }
		session.executeScript(consoleInputText)
		cmdHistory.addToCommandHistory(consoleInputText)
		consoleTextField?.stringValue = ""
	}
	
	// MARK: - SessionOutputHandler
	func append(responseString: ResponseString) {
		// swiftlint:disable:next force_cast
		let mutStr = responseString.string.mutableCopy() as! NSMutableAttributedString
		mutStr.addAttributes([.font: outputFont], range: NSRange(location: 0, length: mutStr.length))
		resultsView!.textStorage?.append(mutStr)
		resultsView!.scrollToEndOfDocument(nil)
	}
	
	func save(state: inout SessionState.OutputControllerState) {
		state.commandHistory = cmdHistory.commands
		let fullRange = resultsView!.textStorage!.string.fullNSRange
		if let rtfd = resultsView?.textStorage?.rtfd(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
		{
			#if DEBUG
			_ = try? rtfd.write(to: URL(fileURLWithPath: "/tmp/lastSession.rtfd"))
			#endif
			state.resultsContent = rtfd
		}
	}

	func restore(state: SessionState.OutputControllerState) {
		cmdHistory.commands = state.commandHistory
		guard let rtfdData = state.resultsContent else { return }
		let resultsView = self.resultsView!
		let ts = resultsView.textStorage!
		//for some reason, NSLayoutManager is initially making the line with an attachment 32 tall, even though image is 48. On window resize, it corrects itself. so we are going to keep an array of attachment indexes so we can fix this later
		var fileIndexes: [Int] = []
		resultsView.replaceCharacters(in: NSRange(location: 0, length: ts.length), withRTFD: rtfdData)
		themeChanged() //trigger setting attributes
		ts.enumerateAttribute(.attachment, in: ts.string.fullNSRange, options: [], using:
		{ (value, range, _) -> Void in
			guard let attach = value as? NSTextAttachment,
				let fw = attach.fileWrapper,
				let fname = fw.preferredFilename
				else { return }
			if fname.hasPrefix("img") {
				let cell = NSTextAttachmentCell(imageCell: #imageLiteral(resourceName: "graph"))
				cell.image?.size = consoleAttachmentImageSize
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
		resultsView.moveToEndOfDocument(self)
	}
	
	func attachmentCellForAttachment(_ attachment: NSTextAttachment) -> NSTextAttachmentCell? {
		guard let attach = try? MacConsoleAttachment.from(data: attachment.fileWrapper!.regularFileContents!) else { return nil }
		assert(attach.type == .file)
		let fileType = FileType.fileType(withExtension: attach.fileExtension!)
		let img = NSImage(named: NSImage.Name(fileType?.iconName ?? "file-plain"))
		img?.size = consoleAttachmentImageSize
		return NSTextAttachmentCell(imageCell: img)
	}
	
	// MARK: - command history
	@IBAction func historyClicked(_ sender: Any?) {
		cmdHistory.adjustCommandHistoryMenu()
		let hframe = historyButton?.superview?.convert((historyButton?.frame)!, to: nil)
		let rect = view.window?.convertToScreen(hframe!)
		cmdHistory.historyMenu.popUp(positioning: nil, at: (rect?.origin)!, in: nil)
	}

	@IBAction func displayHistoryItem(_ sender: Any?) {
		guard let mi = sender as? NSMenuItem, let historyString = mi.representedObject as? String else {
			Log.warn("displayHistoryItem only supported from menu item", .app)
			return
		}
		consoleInputText = historyString
		canExecute = consoleInputText.count > 0
		//the following shouldn't be necessary because they are bound. But sometimes the textfield value does not update
		consoleTextField?.stringValue = consoleInputText
		view.window?.makeFirstResponder(consoleTextField)
	}
	
	@IBAction func clearConsole(_ sender: Any?) {
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
	
	// MARK: - textfield delegate
	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(NSResponder.insertNewline(_:)) {
			executeQuery(control)
			return true
		}
		return false
	}
	
	// MARK: - textview delegate
	func textView(_ textView: NSTextView, clickedOn cell: NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int)
	{
		let attach = cell.attachment
		guard let fw = attach?.fileWrapper else { return }
		viewFileOrImage?(fw)
	}

	// MARK: TextViewMenuDelegate
	@objc func additionalContextMenuItems() -> [NSMenuItem]? {
		var items = contextualMenuDelegate?.contextMenuItems(for: self) ?? []
		for anItem in contextualMenuAdditions?.items ?? [] {
			if let dupItem = anItem.copy() as? NSMenuItem,
				validateMenuItem(dupItem)
			{
				items.append(dupItem)
			}
		}
		return items
	}
}

extension ConsoleOutputController: Searchable {
	func performFind(action: NSTextFinder.Action) {
		let menuItem = NSMenuItem(title: "foo", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
		menuItem.tag = action.rawValue
		resultsView?.performFindPanelAction(menuItem)
		if action == .hideFindInterface {
			resultsView?.enclosingScrollView?.isFindBarVisible = false
		}
	}
}

// MARK: - UsesAdjustableFont
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

