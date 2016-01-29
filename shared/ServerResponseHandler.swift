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

protocol ResponseHandlerDelegate {
	func loadHelpItems(topic:String, items:[HelpItem])
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,JSON>)
	func attributedStringWithImage(image:SessionImage) -> NSAttributedString
	func cacheImages(images:[SessionImage])
}

class ResponseHandler {
	private let delegate:ResponseHandlerDelegate
	private var outputColors: [OutputColors:PlatformColor]

	required init(delegate:ResponseHandlerDelegate) {
		self.delegate = delegate
		let oldDict = NSUserDefaults.standardUserDefaults().dictionaryForKey("OutputColors") as! Dictionary<String,String>
		outputColors = oldDict.reduce([OutputColors:PlatformColor]()) { (var dict, pair) in
			dict[OutputColors(rawValue: pair.0)!] = PlatformColor.colorWithHexString(pair.1)
			return dict
		}
	}

	func handleResponse(response:ServerResponse) -> NSAttributedString? {
		switch(response) {
			case .EchoQuery(let queryId, let fileId, let query):
				return formatQueryEcho(query, queryId:queryId, fileId:fileId)
			case .Results(let queryId, let fileId, let text):
				return formatResults(text, queryId: queryId, fileId: fileId)
			case .Help(let topic, let items):
				delegate.loadHelpItems(topic, items: items)
			case .Error(let queryId, let error):
				return formatError(error, queryId: queryId)
			case .ExecComplete(let queryId, let batchId, let images):
				return formatExecComplete(queryId, batchId: batchId, images: images)
			case .Variable(let socketId, let delta, let single, let variables):
				delegate.handleVariableMessage(socketId, delta: delta, single: single, variables: variables)
		}
		return nil
	}

	private func formatQueryEcho(query:String, queryId:Int, fileId:Int) -> NSAttributedString? {
		let formString = "\(query)\n"
		return NSAttributedString(string: formString, attributes: [NSBackgroundColorAttributeName:outputColors[.Input]!])
	}
	
	private func formatResults(text:String, queryId:Int, fileId:Int) -> NSAttributedString? {
		let formString = "\(text)\n"
		return NSAttributedString(string: formString)
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


