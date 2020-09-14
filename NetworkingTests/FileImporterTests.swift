//
//  FileImporterTests.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

// TODO: this test does not work without Mockingjay
//
//import XCTest
//import Quick
//import Model
//@testable import Networking
//import Mockingjay
//import Rc2Common
//
// //TODO: implement FileImporterTests
//
//class FileImporterTests: NetworkingBaseSpec, URLSessionDataDelegate {
//	private static let foo: Int = {
//		URLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
//		return 1
//	}()
//	func fileUrlsForTesting() -> [URL] {
//		let imgUrl = URL(fileURLWithPath: "/Library/Desktop Pictures/")
//		let files = try! FileManager.default.contentsOfDirectory(at: imgUrl, includingPropertiesForKeys: [URLResourceKey.fileSizeKey], options: [.skipsHiddenFiles])
//		return files
//	}
//
//	override func setUp() {
//		super.setUp()
// //		testWorkspace.files = [testWorkspace.files.first!]
// //		filesToImport = [filesToImport.first!]
//	}
//
//	override func spec() {
//		var conInfo: ConnectionInfo!
//		var wspace: AppWorkspace!
//		var fakeCache: FakeFileCache!
//		let dummyBaseUrl = URL(string: "http://dev.rc2/")!
//		var tmpDirectory: URL!
//		var filesToImport: [FileImporter.FileToImport] = []
//		var expectedFiles: [File] = []
//
//		beforeSuite {
//			tmpDirectory = URL(string: UUID().uuidString, relativeTo: FileManager.default.temporaryDirectory)
//			try! FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true, attributes: nil)
//			filesToImport = self.fileUrlsForTesting().map() { return FileImporter.FileToImport(url: $0, uniqueName: nil) }
//			let aDate = Date(timeIntervalSince1970: 1439407405827)
//			expectedFiles = filesToImport.enumerated().map { (arg) -> File in
//				let (index, file) = arg
//				return File(id: 1000 + index, wspaceId: 100, name: file.fileUrl.lastPathComponent, version: 1, dateCreated: aDate, lastModified: aDate, fileSize: Int(file.fileUrl.fileSize()))
//			}
//		}
//
//		afterSuite {
//			let _ = try? FileManager.default.removeItem(at: tmpDirectory)
//		}
//
//		beforeEach {
//			let data = self.loadFileData("bulkInfo", fileExtension: "json")!
//			conInfo = try! ConnectionInfo(host: .localHost, bulkInfoData: data, authToken: "dfsdgsgdsg")
//			if !(conInfo.urlSessionConfig.protocolClasses?.contains(where: {$0 == MockingjayProtocol.self}) ?? false) {
//				conInfo.urlSessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + conInfo.urlSessionConfig.protocolClasses!
//			}
//			wspace = try! conInfo.workspace(withId: 100, in: try! conInfo.project(withId: 100))
//			fakeCache = FakeFileCache(workspace: wspace, baseUrl: dummyBaseUrl)
//			//TODO: stub REST urls
//			self.stub({ (request) -> (Bool) in
//				return request.url?.absoluteString.hasPrefix(dummyBaseUrl.absoluteString) ?? false
//			}, builder: http(200))
//		}
//
//	}
//}
//
// //	func testSessionMock() {
// // //		let destUri = "/workspaces/1/file/upload"
// // //		stub(uri(destUri), builder:json(expectedFiles.first!, status: 201))
// //		stub(everything, builder:jsonData(expectedFiles.first!.dataUsingEncoding(NSUTF8StringEncoding)!, status: 201))
// //
// //		self.expect = self.expectationWithDescription("upload")
// //		importer = FileImporter(filesToImport, workspace: testWorkspace, baseUrl:NSURL(string: "http://www.google.com/"), configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
// //		{_ in
// //			self.expect?.fulfill()
// //		}
// //		importer?.progress.addObserver(self, forKeyPath: "completedUnitCount", options: .New, context: &kvoContext)
// //		try! importer?.startImport()
// //		self.waitForExpectationsWithTimeout(20) { _ in }
// //		XCTAssertNil(importer?.progress.rc2_error)
// //		XCTAssertEqual(testWorkspace.files.count, filesToImport.count)
// //	}
//
// //protocol of functions we want to test
//protocol URLSessionProtocol {
//	func uploadTaskForFileURL(_ file:URL) -> URLSessionUploadTask
//}
//
//extension URLSession: URLSessionProtocol {
//	func uploadTaskForFileURL(_ file:URL) -> URLSessionUploadTask
//	{
//		let task = uploadTask(with: URLRequest(url: URL(string: "http://www.apple.com/")!), fromFile: file)
//		return task
//	}
//}
//
//class FileImporterSession: NSObject, URLSessionProtocol {
//	var realSession: URLSession
//
//	init(configuration: URLSessionConfiguration, delegate sessionDelegate: URLSessionDelegate?, delegateQueue queue: OperationQueue?)
//	{
//		realSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: queue)
//		super.init()
//	}
//
//	func randomDelay() -> Double {
//		return Double(arc4random_uniform(50)) / 1000.0
//	}
//
//	func uploadTaskForFileURL(_ file:URL) -> URLSessionUploadTask
//	{
//		let myTask = realSession.uploadTask(with: URLRequest(url: URL(string: "http://www.apple.com/")!), fromFile: file)
//		let fsize = Int64(file.fileSize())
//		let halfSize = Int64(fsize / 2)
//		let myDelegate = realSession.delegate as! URLSessionTaskDelegate
//		delay(self.randomDelay())
//		{
//			//receive half the file's data
//			myDelegate.urlSession!(self.realSession, task: myTask, didSendBodyData: halfSize, totalBytesSent: halfSize, totalBytesExpectedToSend: fsize)
//			delay(self.randomDelay()) {
//				//receive the other half
//				myDelegate.urlSession!(self.realSession, task: myTask, didSendBodyData: halfSize, totalBytesSent: fsize, totalBytesExpectedToSend: fsize)
//				myDelegate.urlSession!(self.realSession, task: myTask, didCompleteWithError: nil)
//			}
//		}
//		return myTask
//	}
//
//}
