//
//  DockerLogController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Docker
import ClientCore

enum LogType: Int {
	case combined = 0
	
	static var allValues: [LogType] = [.combined]
	
	var containerType: ContainerType {
		switch self {
			case .combined: return .combined
		}
	}
}

public class DockerLogController: DockerManagerInjectable {
	@IBOutlet private var logView: NSTextView!
	@IBOutlet private var logPopup: NSPopUpButton!
	private var logs: [NSMutableAttributedString] = []
	private var selectedLog: LogType = .combined
	
	public override func viewDidLoad() {
		super.viewDidLoad()
		LogType.allValues.forEach { _ in logs.append(NSMutableAttributedString()) }
		let container = manager!.containers[0]
		DispatchQueue.main.async {
			guard let manager = self.manager else { fatalError() }
			let producer = manager.api.stream(command: ["tail", "-n", "+0", "-f", "/tmp/appserver.stderr.log"], container: container)
			producer.start { [weak self] event in
				guard case let .value(data) = event else { return }
				DispatchQueue.main.async {
					guard let me = self, let str = String(data: data, encoding: .utf8) else { return }
					me.logView.textStorage!.append(NSAttributedString(string: str))
				}
			}
//			LogType.allValues.forEach { logtype in
//				manager.api.streamLog(container: manager.containers[logtype.containerType]!) { [weak self] (str, _) in
//					DispatchQueue.main.async {
//						guard let me = self, let str = str else { return } //TODO: handle close
//						let attrStr = NSAttributedString(string: str)
//						me.logs[logtype.rawValue].append(attrStr)
//						if me.selectedLog == logtype {
//							// figure out if current scrolled to end of document
//							let atEnd = me.logView.enclosingScrollView?.contentView.bounds.maxY ?? 0 == me.logView.enclosingScrollView?.documentView?.bounds.height ?? 0
//							me.logView.textStorage?.append(attrStr)
//							// if was scrolled to end of document, scroll to show newly appended content
//							if atEnd { me.logView.scrollToEndOfDocument(nil) }
//						}
//					}
//				}
//			}
		}
		logView.textStorage?.append(logs[selectedLog.rawValue])
		logView.scrollToEndOfDocument(nil)
	}
	
	@IBAction func desiredLogChanged(_ sender: AnyObject?) {
//		guard let newType = LogType(rawValue: logPopup.selectedTag()) else { fatalError("change to unknown log type") }
//		guard let storage = logView.textStorage else { fatalError("no text storage for log view") }
//		selectedLog = newType
//		storage.replaceCharacters(in: storage.string.fullNSRange, with: logs[selectedLog.rawValue])
		logView.scrollToEndOfDocument(nil)
	}
}
