//
//  SpreadsheetDataSource.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// Provider of data to display in a spreadsheet-like interface
public protocol SpreadsheetDataSource {
	/// number of rows avaiable
	var rowCount: Int { get }
	/// number of columns available
	var columnCount: Int { get }
	/// optional row names
	var rowNames: [String]? { get }
	/// optional column names
	var columnNames: [String]? { get }
	
	/// Returns the contents of a specific row,col combination
	///
	/// - Parameters:
	///   - atRow: the desired row index
	///   - column: the desired column index
	/// - Returns: the string to display for this cell
	func value(atRow: Int, column: Int) -> String
	
	/// Returns the values for a specific column
	///
	/// - Parameter forColumn: the desired column index
	/// - Returns: the strings to display for that column
	func values(forColumn: Int) -> [String]
}
