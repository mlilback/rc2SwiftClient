//
//  EquationViewItem.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SyntaxParsing
import iosMath

class EquationViewItem: NotebookViewItem {
	var equationView: MTMathUILabel!
	
	override func viewDidLoad() {
		let frame = resultTextView!.enclosingScrollView!.frame
		equationView = MTMathUILabel(frame: frame)
		equationView.labelMode = .display
		equationView.contentInsets = MTEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
		equationView.textAlignment = .center
		equationView.autoresizingMask = resultTextView!.autoresizingMask

		resultTextView!.superview!.addSubview(equationView)
		resultTextView?.removeFromSuperview()
		resultTextView = nil

		super.viewDidLoad()
	}
	
	override var nibName: NSNib.Name? { return NSNib.Name(rawValue: "NotebookViewItem") }
	override var resultView: NSView { return equationView }
	override var resultOuterView: NSView { return equationView }
	
	override func prepareForReuse() {
		super.prepareForReuse()
		equationView.latex = ""
	}
	
	override func dataChanged() {
		super.dataChanged()
		guard let inlineEq = data?.chunk as? Equation else { fatalError("chunk not an equation")}
		equationView.latex = inlineEq.equationSource
	}
}
