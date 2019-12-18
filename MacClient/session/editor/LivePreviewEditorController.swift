//
//  LivePreviewEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/30/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import MJLLogger
import ClientCore
import WebKit
import SwiftyUserDefaults

class LivePreviewEditorController: BaseSourceEditorController {
	var outputController: LivePreviewOutputController?
	
	private var webView: WKWebView?
	
	// used to prevent recursion (due to didSet) in outputControllerChanged()
	private var inOutputChange = false

	// used to wrap lastChange with a queue, but that was causing recursive errors. Instead, this values should only be used on the main thread
	private var lastTextChange: TimeInterval = 0
	private var lastChangeTimer: DispatchSourceTimer!
	private var lastChangeRange : NSRange?
	private var lastChangeDelta: Int = 0
	private var timerRunning = false
	
	override func viewDidLoad() {
		super.viewDidLoad()
		editor?.isEditable = true
		lastChangeTimer = DispatchSource.makeTimerSource(queue: .main)
		lastChangeTimer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
		lastChangeTimer.setEventHandler {
			guard let lastRange = self.lastChangeRange, let editor = self.editor else { return }
			let curTime = Date.timeIntervalSinceReferenceDate
			if (curTime - self.lastTextChange) > Defaults[.previewUpdateDelay] {
				self.lastTextChange = curTime
				defer { self.lastChangeRange = nil }
				if let oc = self.outputController,
					oc.contentsEdited(contents: editor.string, range: lastRange, delta: self.lastChangeDelta)
				{
					if self.ignoreContentChanges { return }
					self.save(edits: editor.string, reload: true)
				}
			}
		}
		lastChangeTimer.activate()
		lastChangeTimer.suspend()
	}
	
//	override func loaded(content: String) {
//		do {
//			let rendered = try content.toHTML([.normalize, .safe, .sourcePos])
//			editor?.string = rendered
//		} catch {
//			Log.warn("preview editor failed to parse markdown")
//		}
//	}
	
	override func contentsChanged(_ contents: NSTextStorage, range: NSRange, changeLength delta: Int) {
		super.contentsChanged(contents, range: range, changeLength: delta)
		lastTextChange = Date.timeIntervalSinceReferenceDate
		lastChangeRange = range
		lastChangeDelta = delta
	}
	
	/// subclasses should override and save contents via save(edits:). super should not be called
	override func editsNeedSaving() {
		
	}
	
	func textDidBeginEditing(_ notification: Notification) {
		guard !timerRunning else { return }
		lastChangeTimer.resume()
	}
	
	func textDidEndEditing(_ notification: Notification) {
		lastChangeTimer.suspend()
		timerRunning = false
	}
}
