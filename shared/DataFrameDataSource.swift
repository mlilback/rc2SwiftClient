//
//  DataFrameDataSource.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

public class DataFrameDataSource: SpreadsheetDataSource {
	
	let variable: Variable
	let formatter: VariableFormatter
	let values: [[String]]
	
	public let rowCount: Int
	public let columnCount: Int
	public let rowNames: [String]?
	
	public let columnNames: [String]? // { return dataFrameData.columns.map { $0.name } }
	
	init(variable: Variable, formatter: VariableFormatter) {
		self.variable = variable
		if let matrixData = variable.matrixData {
			// values is rows x columns
			var vals: [[String]] = []
			let strVals = formatter.formatValues(for: matrixData.value)
			for colIdx in 0..<matrixData.colCount {
				let start = colIdx * matrixData.rowCount
				let end   = start + matrixData.rowCount
				vals.append(Array(strVals[start..<end]))
			}
			self.values = vals
			rowCount = matrixData.rowCount
			rowNames = matrixData.rowNames
			columnCount = matrixData.colCount
			columnNames = matrixData.colNames
		} else if let dataFrameData = variable.dataFrameData {
			rowCount = dataFrameData.rowCount
			rowNames = dataFrameData.rowNames
			columnCount = dataFrameData.columns.count
			columnNames = dataFrameData.columns.map{ $0.name }
			values = dataFrameData.columns.map { formatter.formatValues(for: $0.value) }
		} else {
			fatalError("unsupported variable type")
		}
		self.formatter = formatter
		// values is rows x columns
	}
	
	public func value(atRow row: Int, column: Int) -> String {
		return values[column][row]
	}
	
	public 	func values(forColumn: Int) -> [String] {
		return values[forColumn]
	}
}
