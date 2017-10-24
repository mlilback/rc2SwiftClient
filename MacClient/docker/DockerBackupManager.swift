//
//  DockerBackupManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Docker
import ReactiveSwift
import ClientCore
import os
import Result

struct DockerBackup {
	let url: URL
	let date: Date
}

class DockerBackupManager {
	let dockerManager: DockerManager
	let backupDirUrl: URL
	let dateFormatter: ISO8601DateFormatter
	/// broadcasts each time a backup is created
	let backupSignal: Signal<DockerBackup, NoError>
	private let backupObserver: Signal<DockerBackup, NoError>.Observer
	
	/// array of existing backups. Actually reads the file system every time it is referenced
	var backups: [DockerBackup] {
		// create backup struct for every sql file that is a properly formatted date
		do {
			return try FileManager().contentsOfDirectory(at: backupDirUrl, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
			.flatMap { aUrl in
				guard let date = dateFormatter.date(from: aUrl.deletingPathExtension().lastPathComponent),
					aUrl.pathExtension == "sql"
					else { return nil }
				return DockerBackup(url: aUrl, date: date)
			}
		} catch {
			return []
		}
	}
	
	init(manager: DockerManager) {
		dockerManager = manager
		dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withFullDate, .withFullTime]
		do {
			backupDirUrl = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "dbbackup")
		} catch {
			// should never happen, not sure how to handle if it does
			fatalError("failed to locate backup directory \(error)")
		}
		(backupSignal, backupObserver) = Signal<DockerBackup, NoError>.pipe()
	}
	
	/// Performs a backup saving the file to the file system
	///
	/// - Returns: signal producer that returns the created backup object
	func performBackup() -> SignalProducer<DockerBackup, Rc2Error> {
		let backupDate = Date()
		let fileName = dateFormatter.string(from: backupDate) + ".sql"
		let destUrl = backupDirUrl.appendingPathComponent(fileName)
		return dockerManager.backupDatabase(to: destUrl)
			.map { _ in return DockerBackup(url: destUrl, date: backupDate) }
			.on(value: { self.backupObserver.send(value: $0) })
	}
	
	/// restore the database from the specified backup
	///
	/// - Parameter backup: backup to restore
	/// - Returns: signal producer to restore the backup
	func restore(backup: DockerBackup) -> SignalProducer<(), Rc2Error> {
		guard let container = dockerManager.containers[.combined] else { fatalError("no db container") }
		let containerPath = "/rc2/"
		return dockerManager.api.upload(url: backup.url, path: containerPath, filename: "backup.sql", containerName: container.name)
			.mapError { return Rc2Error(type: .docker, nested: $0, explanation: "failed to restore from backup") }
	}
}
