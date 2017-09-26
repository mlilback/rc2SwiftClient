//
//  ServerResponseHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

// swiftlint:disable sorted_imports
#if os(OSX)
	import AppKit
#else
	import UIKit
#endif
import ClientCore
import Freddy
import os
import ReactiveSwift
import Result
import Model

// MARK: Response Formatting -
public protocol SessionResponseFormatterDelegate: class {
	func consoleAttachment(forImage image: SessionImage) -> ConsoleAttachment
	func consoleAttachment(forFile file: File) -> ConsoleAttachment
	func attributedStringForInputFile(_ fileId: Int) -> NSAttributedString
}

/// All function are implemented in an extension
public protocol SessionResponseFormatter {
	var formatterDelegate: SessionResponseFormatterDelegate? { get }
	var outputTheme: OutputTheme { get }
	
	func format(response: SessionResponse, command: SessionCommand) -> ResponseString?
	func formatResults(data: SessionResponse.ResultsData) -> ResponseString?
	func formatOutput(data: SessionResponse.ShowOutputData) -> ResponseString?
	func formatExecComplete(data: SessionResponse.ExecCompleteData) -> ResponseString?
	func formatError(data: SessionResponse.ErrorData) -> ResponseString?
	func formatError(string: String) -> ResponseString?
	func formatEcho(data: SessionResponse.ExecuteData) -> ResponseString?
	func formatFileEcho(data: SessionResponse.ExecuteFileData) -> ResponseString?
}

extension SessionResponseFormatter {
	public func format(response: SessionResponse, command: SessionCommand) -> ResponseString? {
		switch response {
		case .echoExecute(let data):
			return formatEcho(data: data)
		case .echoExecuteFile(let data):
			return formatFileEcho(data: data)
		case .error(let data):
			return formatError(data: data)
		case .execComplete(let data):
			return formatExecComplete(data: data)
		case .results(let data):
			return formatResults(data: data)
		case .showOutput(let data):
			return formatOutput(data: data)
		default:
			return nil
		}
	}

	public func formatResults(data: SessionResponse.ResultsData) -> ResponseString? {
		let mstr = NSMutableAttributedString()
		if !data.output.isEmpty {
			let formString = "\(data.output)\n"
			mstr.append(NSAttributedString(string: formString))
		}
		return ResponseString(string: mstr, type: .output)
	}
	
	public func formatOutput(data: SessionResponse.ShowOutputData) -> ResponseString? {
		let str = formatterDelegate?.consoleAttachment(forFile: data.file).asAttributedString() ?? NSAttributedString()
		// swiftlint:disable:next force_cast (should never fail)
		let mstr = str.mutableCopy() as! NSMutableAttributedString
		mstr.append(NSAttributedString(string: "\n"))
		return ResponseString(string: mstr, type: .attachment)
	}
	
	public func formatExecComplete(data: SessionResponse.ExecCompleteData) -> ResponseString? {
		guard !data.images.isEmpty else { return nil }
		let mstr = NSMutableAttributedString()
		for image in data.images {
			if let aStr = formatterDelegate?.consoleAttachment(forImage: image).asAttributedString() {
				mstr.append(aStr)
			}
		}
		mstr.append(NSAttributedString(string: "\n"))
		return ResponseString(string: mstr, type: .attachment)
	}
	
	public func formatError(string: String) -> ResponseString? {
		let str = NSAttributedString(string: "\(string)\n", attributes: outputTheme.stringAttributes(for: .error))
		return ResponseString(string: str, type: .error)
	}
	
	public func formatError(data: SessionResponse.ErrorData) -> ResponseString? {
		return formatError(string: data.error.localizedDescription)
	}
	
	public func formatEcho(data: SessionResponse.ExecuteData) -> ResponseString? {
		let fstr = NSAttributedString(string: "\(data.source)\n", attributes: outputTheme.stringAttributes(for: .input))
		return ResponseString(string: fstr, type: .input)
	}

	public func formatFileEcho(data: SessionResponse.ExecuteFileData) -> ResponseString? {
		let mstr = NSMutableAttributedString(attributedString: formatterDelegate?.attributedStringForInputFile(data.fileId) ?? NSAttributedString())
		mstr.append(NSAttributedString(string: "\n"))
		mstr.addAttributes(outputTheme.stringAttributes(for: .input), range: NSRange(location: 0, length: mstr.length))
		return ResponseString(string: mstr, type: .input)
	}
}

public class DefaultResponseFormatter: SessionResponseFormatter {
	public weak var formatterDelegate: SessionResponseFormatterDelegate?
	private let _outputTheme: MutableProperty<OutputTheme>
	public var outputTheme: OutputTheme { return _outputTheme.value }
	
	required public init(delegate: SessionResponseFormatterDelegate) {
		self.formatterDelegate = delegate
		_outputTheme = MutableProperty(ThemeManager.shared.activeOutputTheme.value)
		_outputTheme <~ ThemeManager.shared.activeOutputTheme
	}

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

// MARK: Old Stuff -
//public protocol ServerResponseHandlerDelegate: class {
//	func handleFileUpdate(fileId: Int, file: AppFile?, change: FileChangeType)
//	func handleVariableMessage(_ single: Bool, variables: [Variable])
//	func handleVariableDeltaMessage(_ assigned: [Variable], removed: [String])
//	func consoleAttachment(forImage image: SessionImage) -> ConsoleAttachment
//	func consoleAttachment(forFile file: AppFile) -> ConsoleAttachment
//	func attributedStringForInputFile(_ fileId: Int) -> NSAttributedString
//	func showFile(_ fileId: Int)
//}
//
//
//public class ServerResponseHandler {
//	fileprivate weak var delegate: ServerResponseHandlerDelegate?
//	fileprivate let outputTheme: MutableProperty<OutputTheme>
//
//	required public init(delegate: ServerResponseHandlerDelegate) {
//		self.delegate = delegate
//		outputTheme = MutableProperty(ThemeManager.shared.activeOutputTheme.value)
//		outputTheme <~ ThemeManager.shared.activeOutputTheme
//	}
//
//	public func handle(response: SessionResponse) -> ResponseString? {
//		switch response {
//			case .echoQuery(let queryId, let fileId, let query):
//				return formatQueryEcho(query, queryId:queryId, fileId:fileId)
//			case .results(let queryId, let text):
//				return formatResults(text, queryId: queryId)
//			case .error(_, let error):
//				return formatError(error)
//			case .execComplete(let queryId, let batchId, let images):
//				return formatExecComplete(queryId, batchId: batchId, images: images)
//			case .fileChanged(let changeType, let fileId, let file):
//				delegate?.handleFileUpdate(fileId: fileId, file: file, change: FileChangeType(rawValue: changeType)!)
//			case .variables(let single, let variables):
//				delegate?.handleVariableMessage(single, variables: variables)
//			case .variablesDelta(let assigned, let removed):
//				delegate?.handleVariableDeltaMessage(assigned, removed: removed)
//			case .showOutput(let queryId, let updatedFile):
//				let str = formatShowOutput(queryId, file: updatedFile)
//				delegate?.showFile(updatedFile.fileId)
//				return str
//			case .saveResponse( _):
//				//handled by the session, never passed to delegate
//				return nil
//			case .fileOperationResponse(_, _, _):
//				//handled by the session, never passed to delegate
//				return nil
//		}
//		return nil
//	}
//
//	fileprivate func formatQueryEcho(_ query: String, queryId: Int, fileId: Int) -> ResponseString? {
//		if fileId > 0 {
//			let mstr = NSMutableAttributedString(attributedString: delegate!.attributedStringForInputFile(fileId))
//			mstr.append(NSAttributedString(string: "\n"))
//			mstr.addAttributes(outputTheme.value.stringAttributes(for: .input), range: NSRange(location: 0, length: mstr.length))
//			return ResponseString(string: mstr, type: .input)
//		}
//		let fstr = NSAttributedString(string: "\(query)\n", attributes: outputTheme.value.stringAttributes(for: .input))
//		return ResponseString(string: fstr, type: .input)
//	}
//
//	fileprivate func formatResults(_ text: String, queryId: Int) -> ResponseString? {
//		let mstr = NSMutableAttributedString()
//		if !text.characters.isEmpty {
//			let formString = "\(text)\n"
//			mstr.append(NSAttributedString(string: formString))
//		}
//		return ResponseString(string: mstr, type: .output)
//	}
//
//	fileprivate func formatShowOutput(_ queryId: Int, file: AppFile) -> ResponseString? {
//		let str = delegate!.consoleAttachment(forFile:file).asAttributedString()
//		// swiftlint:disable:next force_cast (should never fail)
//		let mstr = str.mutableCopy() as! NSMutableAttributedString
//		mstr.append(NSAttributedString(string: "\n"))
//		return ResponseString(string: mstr, type: .attachment)
//	}
//
//	fileprivate func formatExecComplete(_ queryId: Int, batchId: Int, images: [SessionImage]) -> ResponseString? {
//		guard !images.isEmpty else { return nil }
//		let mstr = NSMutableAttributedString()
//		for image in images {
//			let aStr = delegate!.consoleAttachment(forImage: image).asAttributedString()
//			mstr.append(aStr)
//		}
//		mstr.append(NSAttributedString(string: "\n"))
//		return ResponseString(string: mstr, type: .attachment)
//	}
//
//	public func formatError(_ error: String) -> ResponseString {
//		let str = NSAttributedString(string: "\(error)\n", attributes: outputTheme.value.stringAttributes(for: .error))
//		return ResponseString(string: str, type: .error)
//	}
//}
