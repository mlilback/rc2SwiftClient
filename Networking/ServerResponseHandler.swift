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
import Freddy
import ClientCore
import ReactiveSwift
import Result

public enum FileChangeType : String {
	case Update, Insert, Delete
}

public protocol ServerResponseHandlerDelegate: class {
	func handleFileUpdate(fileId: Int, file:File?, change: FileChangeType)
	func handleVariableMessage(_ single: Bool, variables: [Variable])
	func handleVariableDeltaMessage(_ assigned: [Variable], removed: [String])
	func consoleAttachment(forImage image: SessionImage) -> ConsoleAttachment
	func consoleAttachment(forFile file: File) -> ConsoleAttachment
	func attributedStringForInputFile(_ fileId: Int) -> NSAttributedString
	func showFile(_ fileId: Int)
}

/// encapsulates an attributed string and what that string represents
public struct ResponseString {
	/// Possible types of response strings
	/// - input: an echo of user input
	/// - output: displayable results
	/// - error: an error message
	/// - attachment: links to generated documents or images
	/// - notice: a response that doesn't require the user's attention
	public enum StringType { case input, output, error, attachment, notice }
	/// a response string
	public let string: NSAttributedString
	/// the purpose of the string
	public let type: StringType
}

public class ServerResponseHandler {
	fileprivate weak var delegate: ServerResponseHandlerDelegate?
//	fileprivate let outputColors = OutputColors.colorMap()
	fileprivate var outputTheme: OutputTheme

	required public init(delegate:ServerResponseHandlerDelegate) {
		self.delegate = delegate
		outputTheme = OutputTheme.defaultTheme
		NotificationCenter.default.addObserver(self, selector: #selector(outputThemeChanged(_:)), name: .outputThemeChanged, object: nil)
	}

	public func handleResponse(_ response:ServerResponse) -> ResponseString? {
		switch(response) {
			case .echoQuery(let queryId, let fileId, let query):
				return formatQueryEcho(query, queryId:queryId, fileId:fileId)
			case .results(let queryId, let text):
				return formatResults(text, queryId: queryId)
			case .error(_, let error):
				return formatError(error)
			case .execComplete(let queryId, let batchId, let images):
				return formatExecComplete(queryId, batchId: batchId, images: images)
			case .fileChanged(let changeType, let fileId, let file):
				delegate?.handleFileUpdate(fileId: fileId, file: file, change: FileChangeType.init(rawValue: changeType)!)
			case .variables(let single, let variables):
				delegate?.handleVariableMessage(single, variables: variables)
			case .variablesDelta(let assigned, let removed):
				delegate?.handleVariableDeltaMessage(assigned, removed: removed)
			case .showOutput(let queryId, let updatedFile):
				let str = formatShowOutput(queryId, file: updatedFile)
				delegate?.showFile(updatedFile.fileId)
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

	fileprivate func formatQueryEcho(_ query:String, queryId:Int, fileId:Int) -> ResponseString? {
		if fileId > 0 {
			let mstr = NSMutableAttributedString(attributedString: delegate!.attributedStringForInputFile(fileId))
			mstr.append(NSAttributedString(string: "\n"))
			mstr.addAttributes(outputTheme.stringAttributes(for: .input), range: NSMakeRange(0, mstr.length))
			return ResponseString(string: mstr, type: .input)
		}
		let fstr = NSAttributedString(string: "\(query)\n", attributes: outputTheme.stringAttributes(for: .input))
		return ResponseString(string: fstr, type: .input)
	}
	
	fileprivate func formatResults(_ text:String, queryId:Int) -> ResponseString? {
		let mstr = NSMutableAttributedString()
		if text.characters.count > 0 {
			let formString = "\(text)\n"
			mstr.append(NSAttributedString(string: formString))
		}
		return ResponseString(string: mstr, type: .output)
	}

	fileprivate func formatShowOutput(_ queryId:Int, file:File) -> ResponseString? {
		let str = delegate!.consoleAttachment(forFile:file).asAttributedString()
		let mstr = str.mutableCopy() as! NSMutableAttributedString
		mstr.append(NSAttributedString(string: "\n"))
		return ResponseString(string: mstr, type: .attachment)
	}
	
	fileprivate func formatExecComplete(_ queryId:Int, batchId:Int, images:[SessionImage]) -> ResponseString? {
		guard images.count > 0 else { return nil }
		let mstr = NSMutableAttributedString()
		for image in images {
			let aStr = delegate!.consoleAttachment(forImage: image).asAttributedString()
			mstr.append(aStr)
		}
		mstr.append(NSAttributedString(string: "\n"))
		return ResponseString(string: mstr, type: .attachment)
	}

	public func formatError(_ error:String) -> ResponseString {
		let str = NSAttributedString(string: "\(error)\n", attributes: outputTheme.stringAttributes(for: .error))
		return ResponseString(string: str, type: .error)
	}
	
	@objc fileprivate func outputThemeChanged(_ notification: Notification) {
		outputTheme = notification.object as! OutputTheme
	}
	
}


