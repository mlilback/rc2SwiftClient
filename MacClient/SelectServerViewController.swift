//
//  SelectServerViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import os
import Networking
import ReactiveSwift

class SelectServerViewController: NSViewController, EmbeddedDialogController {
	///specify keys that should trigger KVO notification for canContinue property
	class func keyPathsForValuesAffectingCanContinue() -> Set<String>
	{
		return Set(["selectedServerIndex", "hostName", "login", "password"])
	}
	class func keyPathsForValuesAffectingValuesEditable() -> Set<String>
	{
		return Set(["selectedServerIndex"])
	}

	@IBOutlet var serverMenu: NSPopUpButton?
	@IBOutlet var serverDetailsView: NSStackView?
	@IBOutlet var spinner: NSProgressIndicator?
	@IBOutlet var tabView: NSTabView?
	@IBOutlet var serverNameField: NSTextField?
	
	var bookmarkManager: BookmarkManager?
	@objc dynamic var canContinue: Bool = false
	@objc dynamic var valuesEditable: Bool = false
	@objc dynamic var busy: Bool = false
	@objc dynamic var serverName: String = "" { didSet { adjustCanContinue() } }
	@objc dynamic var hostName: String = "" { didSet { adjustCanContinue() } }
	@objc dynamic var login: String = "" { didSet { adjustCanContinue() } }
	@objc dynamic var password: String = "" { didSet { adjustCanContinue() } }
	var selectedServer: ServerHost?
	fileprivate let keychain = Keychain()
	
	@objc dynamic var selectedServerIndex: Int = 0 { didSet {
		serverDetailsView?.animator().isHidden = selectedServerIndex == 0
		adjustCanContinue()
		let serverCount = (serverMenu?.menu?.items.count)!
		valuesEditable = selectedServerIndex == ((serverCount - 1) )
		if customServerSelected {
			view.window?.makeFirstResponder(serverNameField)
		}
		loadServerHost(serverMenu?.selectedItem?.representedObject as? ServerHost)
	} }
	
	var customServerSelected: Bool { return selectedServerIndex == (serverMenu?.menu?.items.count ?? 0) - 1 }
	var localServerSelected: Bool { return selectedServerIndex == 0 }
	
	// MARK: Methods
	override func viewWillAppear() {
		super.viewWillAppear()
		serverDetailsView?.isHidden = true
		if let menu = serverMenu?.menu {
			menu.removeAllItems()
			menu.addItem(NSMenuItem(title: "Local Server", action: nil, keyEquivalent: ""))
			for aHost in bookmarkManager!.hosts {
				let mi = NSMenuItem(title: aHost.name, action: nil, keyEquivalent: "")
				mi.representedObject = aHost
				menu.addItem(mi)
			}
			menu.addItem(NSMenuItem(title: "New Server…", action: nil, keyEquivalent: ""))
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		selectedServerIndex = 0
		view.window?.visualizeConstraints(view.constraints)
		//disable resizing of view when presented
		preferredContentSize = self.view.frame.size
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		adjustCanContinue()
	}
	
	func loadServerHost(_ host: ServerHost?) {
		serverName = host?.name ?? ""
		hostName = host?.host ?? ""
		login = host?.user ?? ""
		password = keychain.getString("\(login)@\(hostName)") ?? ""
	}
	
	func adjustCanContinue() {
		canContinue = selectedServerIndex == 0 || (serverName.count > 0 && hostName.count > 0 && login.count > 0 && password.count > 0)
	}
	
	func continueAction(_ callback:@escaping (_ value: Any?, _ error: Rc2Error?) -> Void) {
//		let future = attemptLogin()
//		future.onSuccess { (loginsession) in
//			os_log("logged in successfully", log: .app, type: .info)
//			if !(self.bookmarkManager!.hosts.contains(self.selectedServer!)) {
//				self.bookmarkManager?.addHost(self.selectedServer!)
//				self.bookmarkManager?.save()
//				self.savePassword(self.selectedServer!)
//			}
			//for some reason, Xcode 7 compiler crashes if the result tuple is defined in the callback() call
//			let result = SelectServerResponse(server: self.selectedServer, loginSession: loginsession)
//			callback(result, nil)
//			self.busy = false
//		}.onFailure { (error) in
//			callback(nil, error)
			callback(nil, nil)
			self.busy = false
//		}
	}
	
	func savePassword(_ host: ServerHost) {
		do {
			try keychain.setString(host.keychainKey, value: self.password)
		} catch let err as NSError {
			os_log("error saving password: %{public}@", log: .app, type: .info, err)
		}
	}
	
//	func attemptLogin() -> Future<ConnectionInfo, NSError> {
//		valuesEditable = false
//		busy = true
//		var pass = password
//		var server:ServerHost? = nil
//		if let boxedServer = serverMenu?.itemArray[selectedServerIndex].representedObject as? Box<ServerHost> {
//			selectedServer = boxedServer.unbox
//			server = selectedServer
//		} else if selectedServerIndex + 1 == serverMenu?.menu?.items.count {
//			selectedServer = ServerHost(name: serverName, host: hostName, port: defaultAppServerPort, user: login, secure: false)
//			server = selectedServer
//		} else {
//			server = ServerHost.localHost
//			pass = Constants.LocalServerPassword
//		}
//		let restServer = RestServer(host: server!)
//		return restServer.login(pass)
//	}
}
