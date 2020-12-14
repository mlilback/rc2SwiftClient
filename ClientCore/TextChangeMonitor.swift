//
//  TextChangeMonitor.swift
//  ClientCore
//
//  Created by Mark Lilback on 11/23/20.
//  Copyright © 2020 Rc2. All rights reserved.
//

import Cocoa
#if canImport(SwiftyUserDefaults)
import SwiftyUserDefaults
private func defaultPreviewDelay() -> Double { Defaults[.previewUpdateDelay] }
#else
private func defaultPreviewDelay() -> Double { return 0.5 }
#endif

public class TextChangeMonitor {
	
	private var lastTextChange: TimeInterval = 0
	private var lastChangeTimer: DispatchSourceTimer!
	private var lastChangeRange: NSRange?
	private var lastChangeDelta: Int = 0
	private var changedLocation: Int = 0
	private var changedLocationEnd: Int = 0
	public private(set) var timerRunning = false
	
	private let delegate: TextChangeMonitorDelegate
	
	public init(delegate: TextChangeMonitorDelegate) {
		self.delegate = delegate
		lastChangeTimer = DispatchSource.makeTimerSource(queue: .main)
		lastChangeTimer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
		lastChangeTimer.setEventHandler { [weak self] in
			guard let me = self, me.lastTextChange > 0, me.lastChangeRange != nil else { return }
			let curTime = Date.timeIntervalSinceReferenceDate
			if (curTime - me.lastTextChange) > defaultPreviewDelay() {
				print("changedLoc=\(me.changedLocation), delta=\(me.lastChangeDelta), lastChange=\(String(describing: me.lastChangeRange))")
				me.lastTextChange = curTime
				defer { me.lastChangeRange = nil; me.lastChangeDelta = 0}
				let changeRange = NSRange(location: me.changedLocation, length: me.lastChangeDelta)
				delegate.contentsEdited(me, range: changeRange)
			}
		}
		lastChangeTimer.activate()
		lastChangeTimer.suspend()
	}
	
	func contentsChanged(_ contents: NSTextStorage, range: NSRange, changeLength delta: Int) {
		// really does nothing, but call to be safe
		lastTextChange = Date.timeIntervalSinceReferenceDate
		if lastChangeRange == nil {
			lastChangeRange = range
			changedLocation = range.location
			changedLocationEnd = changedLocation
		}
		changedLocation = max(0, min(range.location, changedLocation))
		changedLocationEnd = max(range.location, changedLocationEnd)
		// Take the difference, and add one to account for the start index.
		lastChangeDelta = changedLocationEnd - changedLocation + 1
	}
	
	public func textChanged(range: NSRange, delta: Int) {
		print("tc: \(range) \(delta)")
		lastTextChange = Date.timeIntervalSinceReferenceDate
		if lastChangeRange == nil {
			lastChangeRange = range
			changedLocation = range.location
			changedLocationEnd = changedLocation
		}
		// Set lower bound to capture lowest index and upper bound to capture the largest index
		changedLocation = max(0, min(range.location, changedLocation))
		changedLocationEnd = max(range.location, changedLocationEnd)
		// Take the difference, and add one to account for the start index.
		lastChangeDelta = changedLocationEnd - changedLocation + 1
	}
	
	public func didBeginEditing() {
		guard !timerRunning else { return }
		lastChangeTimer.resume()
	}
	
	public func didEndEditing() {
		lastChangeTimer.suspend()
		timerRunning = false
	}
}

public protocol TextChangeMonitorDelegate {
	func contentsEdited(_ monitor: TextChangeMonitor, range: NSRange)
}
