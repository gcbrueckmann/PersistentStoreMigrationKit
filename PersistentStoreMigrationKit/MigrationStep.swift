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
    
    private var progress: Progress?
    
    /// Performs the migration from the persistent store identified by `sourceURL` and using `sourceModel` to `destinationModel`, saving the result in the persistent store identified by `destinationURL`.
    /// 
    /// Inserts an `NSProgress` instance into the current progress tree.
    /// 
    /// - Parameters:
    ///   - sourceURL: Identifies the persistent store to migrate from.
    ///   - sourceStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the source store type.
    ///   - destinationURL: Identifies the persistent store to migrate to. May be identical to `sourceURL`.
    ///   - destinationStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the destination store type.
    func executeForStoreAtURL(_ sourceURL: URL, type sourceStoreType: String, destinationURL: URL, storeType destinationStoreType: String) throws {
        let progress = Progress(totalUnitCount: 100)
        self.progress = progress
        defer { self.progress = nil }

        let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
        let migrationProgressObserver = migrationManager.observe(\.migrationProgress, options: .new) { (_, change) in
            guard let migrationProgress = change.newValue else { preconditionFailure("Observed change should always have a value.") }
            progress.completedUnitCount = Int64(migrationProgress * 100)
        }
        defer { migrationProgressObserver.invalidate() }

        try migrationManager.migrateStore(from: sourceURL, sourceType: sourceStoreType, options: nil, with: mappingModel, toDestinationURL: destinationURL, destinationType: destinationStoreType, destinationOptions: nil)
    }
}
