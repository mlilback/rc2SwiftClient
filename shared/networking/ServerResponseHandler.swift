//
//  ServerResponseHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

#if os(OSX)
	import Cocoa
#else
	import UIKit
#endif
import SwiftyJSON


enum FileChangeType : String {
	case Update, Insert, Delete
}

protocol ServerResponseHandlerDelegate {
	func handleFileUpdate(file:File, change:FileChangeType)
	func handleVariableMessage(single:Bool, variables:[Variable])
	func handleVariableDeltaMessage(assigned:[Variable], removed:[String])
	func consoleAttachment(forImage image:SessionImage) -> ConsoleAttachment
	func consoleAttachment(forFile file:File) -> ConsoleAttachment
	func attributedStringForInputFile(fileId:Int) -> NSAttributedString
	func cacheImages(images:[SessionImage])
	func showFile(fileId:Int)
}

class ServerResponseHandler {
	private let delegate:ServerResponseHandlerDelegate
	private let outputColors = OutputColors.colorMap()

	required init(delegate:ServerResponseHandlerDelegate) {
		self.delegate = delegate
	}

	func handleResponse(response:ServerResponse) -> NSAttributedString? {
		switch(response) {
			case .EchoQuery(let queryId, let fileId, let query):
				return formatQueryEcho(query, queryId:queryId, fileId:fileId)
			case .Results(let queryId, let text):
				return formatResults(text, queryId: queryId)
			case .Error(_, let error):
				return formatError(error)
			case .ExecComplete(let queryId, let batchId, let images):
				return formatExecComplete(queryId, batchId: batchId, images: images)
			case .FileChanged(let changeType, let file):
				delegate.handleFileUpdate(file, change: FileChangeType.init(rawValue: changeType)!)
			case .Variables(let single, let variables):
				delegate.handleVariableMessage(single, variables: variables)
			case .VariablesDelta(let assigned, let removed):
				delegate.handleVariableDeltaMessage(assigned, removed: removed)
			case .ShowOutput(let queryId, let updatedFile):
				let str = formatShowOutput(queryId, file:updatedFile)
				delegate.showFile(updatedFile.fileId)
				return str
			case .SaveResponse( _):
				//handled by the session, never passed to delegate
				return nil
			case .FileOperationResponse(_, _, _):
				//handled by the session, never passed to delegate
				return nil
		}
		return nil
	}

	private func formatQueryEcho(query:String, queryId:Int, fileId:Int) -> NSAttributedString? {
		if fileId > 0 {
			let mstr = NSMutableAttributedString(attributedString: delegate.attributedStringForInputFile(fileId))
			mstr.appendAttributedString(NSAttributedString(string: "\n"))
			mstr.addAttribute(NSBackgroundColorAttributeName, value: outputColors[.Input]!, range: NSMakeRange(0, mstr.length))
			return mstr
		}
		return NSAttributedString(string: "\(query)\n", attributes: [NSBackgroundColorAttributeName:outputColors[.Input]!])
	}
	
	private func formatResults(text:String, queryId:Int) -> NSAttributedString? {
		let mstr = NSMutableAttributedString()
		if text.characters.count > 0 {
			let formString = "\(text)\n"
			mstr.appendAttributedString(NSAttributedString(string: formString))
		}
		return mstr
	}

	private func formatShowOutput(queryId:Int, file:File) -> NSAttributedString? {
		let str = delegate.consoleAttachment(forFile:file).serializeToAttributedString()
		let mstr = str.mutableCopy() as! NSMutableAttributedString
		mstr.appendAttributedString(NSAttributedString(string: "\n"))
		return mstr
	}
	
	private func formatExecComplete(queryId:Int, batchId:Int, images:[SessionImage]) -> NSAttributedString? {
		guard images.count > 0 else { return nil }
		delegate.cacheImages(images)
		let mstr = NSMutableAttributedString()
		for image in images {
			let aStr = delegate.consoleAttachment(forImage: image).serializeToAttributedString()
			mstr.appendAttributedString(aStr)
		}
		mstr.appendAttributedString(NSAttributedString(string: "\n"))
		return mstr
	}

	func formatError(error:String) -> NSAttributedString {
		return NSAttributedString(string: "\(error)\n", attributes: [NSBackgroundColorAttributeName:outputColors[.Error]!])
	}
}


