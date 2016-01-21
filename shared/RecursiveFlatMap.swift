//
//  RecursiveFlatMap.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

///returns array of all recursive children of root that pass the test in transform
//
//ideally transform and children weould be @noescape, but you can't call another 
// noescape function, even though it should be fine with the same functiuon
func recursiveFlatMap<T, TResult>(root: T, transform: (T) -> TResult?, children: (T) -> [T]) -> [TResult]
{
	var result = [TResult]()
	if let value = transform(root) {
		result.append(value)
	}
	result += children(root).flatMap( { recursiveFlatMap($0, transform: transform, children: children) })
	return result
}
