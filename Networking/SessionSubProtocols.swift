//
//  SessionSubProtocols
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
import ReactiveSwift

public protocol FileSaver {
	var workspace: AppWorkspace { get }
	/// Saves the file to the cache and remote server
	///
	/// - Parameters:
	///   - file: the file to save
	///   - contents: the contents to save. If nil will return an error
	/// - Returns: SP that will save the files to the cache and server
	func save(file: AppFile, contents: String?) -> SignalProducer<Void, Rc2Error>
}
