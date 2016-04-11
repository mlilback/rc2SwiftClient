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

protocol ResponseHandlerDelegate {
	func loadHelpItems(topic:String, items:[HelpItem])
	func handleFileUpdate(file:File, change:FileChangeType)
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,JSON>)
	func attributedStringWithImage(image:SessionImage) -> NSAttributedString
	func attributedStringWithFile(file:File) -> NSAttributedString
	func cacheImages(images:[SessionImage])
}

class ResponseHandler {
	private let delegate:ResponseHandlerDelegate
	private var outputColors: [OutputColors:PlatformColor]

	required init(delegate:ResponseHandlerDelegate) {
		self.delegate = delegate
		let oldDict = NSUserDefaults.standardUserDefaults().dictionaryForKey("OutputColors") as! Dictionary<String,String>
		outputColors = oldDict.reduce([OutputColors:PlatformColor]()) { (dict, pair) in
			var aDict = dict
			aDict[OutputColors(rawValue: pair.0)!] = PlatformColor.colorWithHexString(pair.1)
			return aDict
		}
	}

	func handleResponse(response:ServerResponse) -> NSAttributedString? {
		switch(response) {
			case .EchoQuery(let queryId, let fileId, let query):
				return formatQueryEcho(query, queryId:queryId, fileId:fileId)
			case .Results(let queryId, let text):
				return formatResults(text, queryId: queryId)
			case .Help(let topic, let items):
				delegate.loadHelpItems(topic, items: items)
			case .Error(let queryId, let error):
				return formatError(error, queryId: queryId)
			case .ExecComplete(let queryId, let batchId, let images):
				return formatExecComplete(queryId, batchId: batchId, images: images)
			case .FileChanged(let changeType, let file):
				delegate.handleFileUpdate(file, change: FileChangeType.init(rawValue: changeType)!)
			case .Variable(let socketId, let delta, let single, let variables):
				delegate.handleVariableMessage(socketId, delta: delta, single: single, variables: variables)
			case .ShowOutput(let queryId, let updatedFile):
				return formatShowOutput(queryId, file:updatedFile)
			case .SaveResponse( _):
				//handled by the session, never passed to delegate
				return nil
		}
		return nil
	}

	private func formatQueryEcho(query:String, queryId:Int, fileId:Int) -> NSAttributedString? {
		let formString = "\(query)\n"
		return NSAttributedString(string: formString, attributes: [NSBackgroundColorAttributeName:outputColors[.Input]!])
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
		return delegate.attributedStringWithFile(file)
	}
	
	private func formatExecComplete(queryId:Int, batchId:Int, images:[SessionImage]) -> NSAttributedString? {
		guard images.count > 0 else { return nil }
		delegate.cacheImages(images)
		let mstr = NSMutableAttributedString()
		for image in images {
			let aStr = delegate.attributedStringWithImage(image)
			mstr.appendAttributedString(aStr)
		}
		mstr.appendAttributedString(NSAttributedString(string: "\n"))
		return mstr
	}

	private func formatError(error:String, queryId:Int) -> NSAttributedString? {
		return NSAttributedString(string: "\(error)\n", attributes: [NSBackgroundColorAttributeName:outputColors[.Error]!])
	}
}


