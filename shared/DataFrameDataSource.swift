//
//  DataFrameDataSource.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

public class DataFrameDataSource: SpreadsheetDataSource {
	
	let variable: Variable
	let dataFrameData: DataFrameData
	let formatter: VariableFormatter
	let values: [[String]]
	
	public var rowCount: Int { return dataFrameData.rowCount }
	
	public var columnCount: Int { return dataFrameData.columns.count }
	
	public var rowNames: [String]? { return dataFrameData.rowNames }
	
	public var columnNames: [String]? { return dataFrameData.columns.map { $0.name } }
	
	init(variable: Variable, data: DataFrameData, formatter: VariableFormatter) {
		self.variable = variable
		self.dataFrameData = data
		self.formatter = formatter
		// values is rows x columns
		self.values = data.columns.map { formatter.formatValues(for: $0.value) }
	}
	
	public func value(atRow row: Int, column: Int) -> String {
		return values[column][row]
	}
	
	
}
