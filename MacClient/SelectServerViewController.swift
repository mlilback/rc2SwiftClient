//
//  SelectServerViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import BrightFutures

struct SelectServerResponse {
	let server:ServerHost
	let loginSession:LoginSession
}

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
	@IBOutlet var spinner:NSProgressIndicator?
	@IBOutlet var tabView:NSTabView?
	@IBOutlet var serverNameField: NSTextField?
	
	var bookmarkManager: BookmarkManager?
	dynamic var canContinue:Bool = false
	dynamic var valuesEditable:Bool = false
	dynamic var busy:Bool = false
	dynamic var serverName:String = "" { didSet { adjustCanContinue() } }
	dynamic var hostName:String = "" { didSet { adjustCanContinue() } }
	dynamic var login:String = "" { didSet { adjustCanContinue() } }
	dynamic var password:String = "" { didSet { adjustCanContinue() } }
	var selectedServer:ServerHost?
	private let keychain = Keychain()
	
	dynamic var selectedServerIndex:Int = 0 { didSet {
		serverDetailsView?.animator().hidden = selectedServerIndex == 0
		adjustCanContinue()
		let serverCount = (serverMenu?.menu?.itemArray.count)!
		valuesEditable = selectedServerIndex == ((serverCount - 1) ?? 0)
		if customServerSelected {
			view.window?.makeFirstResponder(serverNameField)
		}
		loadServerHost((serverMenu?.selectedItem?.representedObject as? Box<ServerHost>)?.unbox)
	} }
	
	var customServerSelected:Bool { return selectedServerIndex == (serverMenu?.menu?.itemArray.count ?? 0) - 1 }
	var localServerSelected:Bool { return selectedServerIndex == 0 }
	
	override func viewWillAppear() {
		super.viewWillAppear()
		serverDetailsView?.hidden = true
		if let menu = serverMenu?.menu {
			menu.removeAllItems()
			menu.addItem(NSMenuItem(title: "Local Server", action: nil, keyEquivalent: ""))
			for aHost in bookmarkManager!.hosts {
				let mi = NSMenuItem(title: aHost.name, action: nil, keyEquivalent: "")
				mi.representedObject = Box<ServerHost>(aHost)
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
	
	func loadServerHost(host:ServerHost?) {
		serverName = host?.name ?? ""
		hostName = host?.host ?? ""
		login = host?.user ?? ""
		password = keychain.getString("\(login)@\(hostName)") ?? ""
	}
	
	func adjustCanContinue() {
		canContinue = selectedServerIndex == 0 || (serverName.characters.count > 0 && hostName.characters.count > 0 && login.characters.count > 0 && password.characters.count > 0)
	}
	
	func continueAction(callback:(value:Any?, error:NSError?) -> Void) {
		let future = attemptLogin()
		future.onSuccess { (loginsession) in
			log.info("logged in successfully")
			if !(self.bookmarkManager!.hosts.contains(self.selectedServer!)) {
				self.bookmarkManager?.addHost(self.selectedServer!)
				self.bookmarkManager?.save()
				self.savePassword()
			}
			//for some reason, Xcode 7 compiler crashes if the result tuple is defined in the callback() call
			let result = SelectServerResponse(server: self.selectedServer!, loginSession: loginsession)
			callback(value:result, error:nil)
			self.busy = false
		}.onFailure { (error) in
			callback(value: nil, error: error)
			self.busy = false
		}
	}
	
	func savePassword() {
		do {
			try keychain.setString("\(self.login)@\(self.hostName)", value: self.password)
		} catch let err as NSError {
			log.info("error saving password: \(err)")
		}
	}
	
	func attemptLogin() -> Future<LoginSession, NSError> {
		valuesEditable = false
		busy = true
		var pass = password
		if let boxedServer = serverMenu?.itemArray[selectedServerIndex].representedObject as? Box<ServerHost> {
			selectedServer = boxedServer.unbox
		} else if selectedServerIndex + 1 == serverMenu?.menu?.itemArray.count {
			selectedServer = ServerHost(name: serverName, host: hostName, port: 8088, user: login, secure: false)
		} else {
			selectedServer = ServerHost(name: "Local Server", host: "localhost", port: 8088, user: "test", secure: false)
			pass = "beavis"
		}
		let restServer = RestServer(host: selectedServer!)
		return restServer.login(pass)
	}
}
