//
//  ServerResponseHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol ResponseHandlerDelegate {
	func loadHelpItems(topic:String, items:[HelpItem])
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,JSON>)
}

class ResponseHandler {
	typealias ResponseOutput = (string:NSAttributedString, images:[NSURL]?)?

	private let baseImageUrl:NSURL
	private let delegate:ResponseHandlerDelegate
	
	required init(imageDirectory:NSURL, delegate:ResponseHandlerDelegate) {
		self.delegate = delegate
		self.baseImageUrl = imageDirectory
	}

	func handleResponse(response:ServerResponse) -> ResponseOutput {
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

	private func formatQueryEcho(query:String, queryId:Int, fileId:Int) -> ResponseOutput {
		let outStr = NSMutableAttributedString()
		outStr.mutableString.appendFormat("%@\n", query)
		return (outStr, nil)
	}
	
	private func formatResults(text:String, queryId:Int, fileId:Int) -> ResponseOutput {
		let outStr = NSMutableAttributedString()
		outStr.mutableString.appendFormat("%@\n", text)
		return (outStr, nil)
	}

	private func formatExecComplete(queryId:Int, batchId:Int, images:[SessionImage]) -> ResponseOutput {
		let outStr = NSMutableAttributedString()
		return (outStr, nil)
	}

	private func formatError(error:String, queryId:Int) -> ResponseOutput {
		let outStr = NSMutableAttributedString()
		return (outStr, nil)
	}
}


