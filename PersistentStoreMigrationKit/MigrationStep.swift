//
//  MigrationStep.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg C. Brückmann on 26.08.15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData

/// A `MigrationStep` instance encapsulates the migration from one `NSManagedObjectModel` to another without any intermediate models.
/// Migration is performed via an `NSMigrationManager` using an `NSMappingModel`.
final class MigrationStep: NSObject {
	/// Specifies how to from `sourceModel` to `destinationModel`.
	let mappingModel: NSMappingModel
	/// The model to migrate from.
	let sourceModel: NSManagedObjectModel
	/// The model to migrate to.
	let destinationModel: NSManagedObjectModel
	
	private var keyValueObservingContext = NSUUID().UUIDString
	
	/// Initializes a migration step for a source model, destination model, and a mapping model.
	/// 
	/// - Parameters:
	///   - sourceModel: The model to migrate from.
	///   - destinationModel: The model to migrate to.
	///   - mappingModel: Specifies how to from `sourceModel` to `destinationModel`.
	init(sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel, mappingModel: NSMappingModel) {
		self.sourceModel = sourceModel
		self.destinationModel = destinationModel
		self.mappingModel = mappingModel
	}
	
	private var progress: NSProgress?
	
	/// Performs the migration from the persistent store identified by `sourceURL` and using `sourceModel` to `destinationModel`, saving the result in the persistent store identified by `destinationURL`.
	/// 
	/// Inserts an `NSProgress` instance into the current progress tree.
	/// 
	/// - Parameters:
	///   - sourceURL: Identifies the persistent store to migrate from.
	///   - sourceStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the source store type.
	///   - destinationURL: Identifies the persistent store to migrate to. May be identical to `sourceURL`.
	///   - destinationStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the destination store type.
	func executeForStoreAtURL(sourceURL: NSURL, type sourceStoreType: String, destinationURL: NSURL, storeType destinationStoreType: String) throws {
		progress = NSProgress(totalUnitCount: 100)
		defer { progress = nil }
		let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
		migrationManager.addObserver(self, forKeyPath: "migrationProgress", options: .New, context: &keyValueObservingContext)
		defer { migrationManager.removeObserver(self, forKeyPath: "migrationProgress", context: &keyValueObservingContext) }
		try migrationManager.migrateStoreFromURL(sourceURL, type: sourceStoreType, options: nil, withMappingModel: mappingModel, toDestinationURL: destinationURL, destinationType: destinationStoreType, destinationOptions: nil)
	}
	
	// MARK: NSKeyValueObserving
	override func observeValueForKeyPath(keyPath: String!, ofObject object: AnyObject!, change: [String : AnyObject]!, context: UnsafeMutablePointer<Void>) {
		if context != &keyValueObservingContext {
			super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
			return
		}
		if let _ = object as? NSMigrationManager {
			switch keyPath {
			case "migrationProgress":
				let newMigrationProgress = (change[NSKeyValueChangeNewKey] as! NSNumber).floatValue
				progress?.completedUnitCount = Int64(newMigrationProgress * 100)
			default:
				break
			}
		}
	}
}
