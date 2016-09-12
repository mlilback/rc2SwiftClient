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
	func handleFileUpdate(_ file:File, change:FileChangeType)
	func handleVariableMessage(_ single:Bool, variables:[Variable])
	func handleVariableDeltaMessage(_ assigned:[Variable], removed:[String])
	func consoleAttachment(forImage image:SessionImage) -> ConsoleAttachment
	func consoleAttachment(forFile file:File) -> ConsoleAttachment
	func attributedStringForInputFile(_ fileId:Int) -> NSAttributedString
	func cacheImages(_ images:[SessionImage])
	func showFile(_ fileId:Int)
}

class ServerResponseHandler {
	fileprivate let delegate:ServerResponseHandlerDelegate
	fileprivate let outputColors = OutputColors.colorMap()

	required init(delegate:ServerResponseHandlerDelegate) {
		self.delegate = delegate
	}

	func handleResponse(_ response:ServerResponse) -> NSAttributedString? {
		switch(response) {
			case .echoQuery(let queryId, let fileId, let query):
				return formatQueryEcho(query, queryId:queryId, fileId:fileId)
			case .results(let queryId, let text):
				return formatResults(text, queryId: queryId)
			case .error(_, let error):
				return formatError(error)
			case .execComplete(let queryId, let batchId, let images):
				return formatExecComplete(queryId, batchId: batchId, images: images)
			case .fileChanged(let changeType, let file):
				delegate.handleFileUpdate(file, change: FileChangeType.init(rawValue: changeType)!)
			case .variables(let single, let variables):
				delegate.handleVariableMessage(single, variables: variables)
			case .variablesDelta(let assigned, let removed):
				delegate.handleVariableDeltaMessage(assigned, removed: removed)
			case .showOutput(let queryId, let updatedFile):
				let str = formatShowOutput(queryId, file:updatedFile)
				delegate.showFile(updatedFile.fileId)
				return str
			case .saveResponse( _):
				//handled by the session, never passed to delegate
				return nil
			case .fileOperationResponse(_, _, _):
				//handled by the session, never passed to delegate
				return nil
		}
		return nil
	}

	fileprivate func formatQueryEcho(_ query:String, queryId:Int, fileId:Int) -> NSAttributedString? {
		if fileId > 0 {
			let mstr = NSMutableAttributedString(attributedString: delegate.attributedStringForInputFile(fileId))
			mstr.append(NSAttributedString(string: "\n"))
			mstr.addAttribute(NSBackgroundColorAttributeName, value: outputColors[.Input]!, range: NSMakeRange(0, mstr.length))
			return mstr
		}
		return NSAttributedString(string: "\(query)\n", attributes: [NSBackgroundColorAttributeName:outputColors[.Input]!])
	}
	
	fileprivate func formatResults(_ text:String, queryId:Int) -> NSAttributedString? {
		let mstr = NSMutableAttributedString()
		if text.characters.count > 0 {
			let formString = "\(text)\n"
			mstr.append(NSAttributedString(string: formString))
		}
		return mstr
	}

	fileprivate func formatShowOutput(_ queryId:Int, file:File) -> NSAttributedString? {
		let str = delegate.consoleAttachment(forFile:file).serializeToAttributedString()
		let mstr = str.mutableCopy() as! NSMutableAttributedString
		mstr.append(NSAttributedString(string: "\n"))
		return mstr
	}
	
	fileprivate func formatExecComplete(_ queryId:Int, batchId:Int, images:[SessionImage]) -> NSAttributedString? {
		guard images.count > 0 else { return nil }
		delegate.cacheImages(images)
		let mstr = NSMutableAttributedString()
		for image in images {
			let aStr = delegate.consoleAttachment(forImage: image).serializeToAttributedString()
			mstr.append(aStr)
		}
		mstr.append(NSAttributedString(string: "\n"))
		return mstr
	}

	func formatError(_ error:String) -> NSAttributedString {
		return NSAttributedString(string: "\(error)\n", attributes: [NSBackgroundColorAttributeName:outputColors[.Error]!])
	}
}


