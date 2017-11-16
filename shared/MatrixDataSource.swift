//
//  MatrixDataSource.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

public class MatrixDataSource: SpreadsheetDataSource {
	let variable: Variable
	let matrixData: MatrixData
	let values: [[String]]
	
	public var rowCount: Int { return matrixData.rowCount }
	
	public var columnCount: Int { return matrixData.colCount }
	
	public var rowNames: [String]? { return matrixData.rowNames }
	
	public var columnNames: [String]? { return matrixData.colNames }
	
	init(variable: Variable, data: MatrixData, values: [String]) {
		self.variable = variable
		self.matrixData = data
		// values is rows x columns
		var vals: [[String]] = []
		for colIdx in 0..<data.colCount {
			let start = colIdx * data.rowCount
			let end   = start + data.rowCount
			vals.append(Array(values[start..<end]))
		}
		self.values = vals
	}
	
	public func value(atRow row: Int, column: Int) -> String {
		return values[column][row]
	}
	
	
}
