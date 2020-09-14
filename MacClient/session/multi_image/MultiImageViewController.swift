//
//  MultiImageViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking

class MultiImageViewController: NSViewController {
	var session: Session! { didSet { print("got session") } }
	@IBOutlet var collection: NSCollectionView!

	override func viewDidLoad() {
		super.viewDidLoad()
		print("view loaded")
	}

	@IBAction func shareImages(_ sender: Any?) {
		print("share")
	}

	@IBAction func changeLayout(_ sender: Any?) {
		print("change layout")
	}
}
