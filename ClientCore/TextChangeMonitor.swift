//
//  TextChangeMonitor.swift
//  ClientCore
//
//  Created by Mark Lilback on 11/23/20.
//  Copyright © 2020 Rc2. All rights reserved.
//

import Foundation
import SwiftyUserDefaults

public class TextChangeMonitor {
	
	private var lastTextChange: TimeInterval = 0
	private var lastChangeTimer: DispatchSourceTimer!
	private var lastChangeRange: NSRange?
	private var lastChangeDelta: Int = 0
	public private(set) var timerRunning = false
	private var lastChangeMaxDelta: Int = 0
	private var changedLocation: Int = 0
	private let delegate: TextChangeMonitorDelegate
	
	public init(delegate: TextChangeMonitorDelegate) {
		self.delegate = delegate
		lastChangeTimer = DispatchSource.makeTimerSource(queue: .main)
		lastChangeTimer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
		lastChangeTimer.setEventHandler { [weak self] in
			guard let me = self else { return }
			let curTime = Date.timeIntervalSinceReferenceDate
			if (curTime - me.lastTextChange) > Defaults[.previewUpdateDelay] {
				me.lastTextChange = curTime
				defer { me.lastChangeRange = nil; me.lastChangeDelta = 0 }
				let changeRange = NSRange(location: me.changedLocation, length: me.lastChangeDelta)
				delegate.contentsEdited(me, range: changeRange, delta: me.lastChangeMaxDelta)
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
		}
		if delta < 0 {
			changedLocation += delta
		}
		lastChangeDelta += abs(delta)
	}
	
	public func textChanged(range: NSRange, delta: Int) {
		lastTextChange = Date.timeIntervalSinceReferenceDate
		if lastChangeRange == nil {
			lastChangeRange = range
			changedLocation = range.location
		}
		if delta < 0 {
			changedLocation += delta
		}
		lastChangeDelta += abs(delta)

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
	func contentsEdited(_ monitor: TextChangeMonitor, range: NSRange, delta: Int)
}
