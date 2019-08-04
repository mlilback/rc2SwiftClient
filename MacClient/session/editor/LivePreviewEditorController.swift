//
//  LivePreviewEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/30/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import Down
import MJLLogger
import ClientCore
import WebKit

let typingDelayBeforeUpdatingPreview: TimeInterval = 0.4

class LivePreviewEditorController: BaseSourceEditorController {
	var outputController: LivePreviewOutputController? { didSet { outputControllerChanged() } }
	
	private var webView: WKWebView?
	private var inChange = false
	private var lastTextChange: TimeInterval = 0
	private let lastChangeQueue = DispatchQueue(label: "preview text change")
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
			self.lastChangeQueue.sync {
				guard let lastRange = self.lastChangeRange else { return }
				let curTime = Date.timeIntervalSinceReferenceDate
				if (curTime - self.lastTextChange) > typingDelayBeforeUpdatingPreview {
					self.lastTextChange = curTime
					defer { self.lastChangeRange = nil }
					if let oc = self.outputController,
						oc.contentsEdited(range: lastRange, delta: self.lastChangeDelta),
						let newContents = self.editor?.string
					{
						self.save(edits: newContents)
					}
				}
			}
		}
//		lastChangeQueue.sync {
			lastChangeTimer.activate()
			lastChangeTimer.suspend()
//		}
	}

	override func setContext(context: EditorContext) {
		super.setContext(context: context)
		outputController?.editorContext = context
	}
	
	// outputControllerChanged was being called recursively. Use inChange flag to prevent that
	func outputControllerChanged() {
		guard !inChange else { return }
		inChange = true
		defer { inChange = false }
		outputController?.editorContext = self.context
		// need to update with current generated contents
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
		lastChangeQueue.sync {
			lastTextChange = Date.timeIntervalSinceReferenceDate
			lastChangeRange = range
			lastChangeDelta = delta
		}
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
