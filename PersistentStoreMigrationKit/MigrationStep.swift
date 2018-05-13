//
//  MigrationStep.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg C. Brückmann on 26.08.15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData

/// A migration step encapsulates the migration from one `NSManagedObjectModel` to another without any intermediate models.
///
/// Source and destination models can be the same (if you want to copy stores without changing the model).
struct MigrationStep {
    
    /// Specifies how to from `sourceModel` to `destinationModel`.
    let mappingModel: NSMappingModel?
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

    /// Initializes a migration step for single source and destination model.
    ///
    /// - parameters model: The model to migrate from and to.
    init(model: NSManagedObjectModel) {
        self.sourceModel = model
        self.destinationModel = model
        self.mappingModel = nil
    }
    
    /// Performs the migration from the persistent store identified by `sourceURL` and using `sourceModel` to `destinationModel`, saving the result in the persistent store identified by `destinationURL`.
    /// 
    /// Inserts an `NSProgress` instance into the current progress tree.
    /// 
    /// - Parameters:
    ///   - sourceURL: Identifies the persistent store to migrate from.
    ///   - sourceStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the source store type.
    ///   - destinationURL: Identifies the persistent store to migrate to. May be identical to `sourceURL`.
    ///   - destinationStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the destination store type.
    func executeForStore(at sourceURL: URL, type sourceStoreType: String, destinationURL: URL, storeType destinationStoreType: String) throws {
        let progress = Progress(totalUnitCount: 100)

        let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
        let migrationProgressObserver = migrationManager.observe(\.migrationProgress, options: .new) { (_, change) in
            guard let migrationProgress = change.newValue else { preconditionFailure("Observed change should always have a value.") }
            progress.completedUnitCount = Int64(migrationProgress * 100)
        }
        defer { migrationProgressObserver.invalidate() }

        try migrationManager.migrateStore(from: sourceURL, sourceType: sourceStoreType, options: nil, with: mappingModel, toDestinationURL: destinationURL, destinationType: destinationStoreType, destinationOptions: nil)
    }
}

extension MigrationStep {

    /// Figures out which steps need to be performed to migrate an existing to a destination model.
    ///
    /// - parameter storeMetadata: The metadata of an existing persistent store.
    /// - parameter destinationModel: The model to migrate to.
    /// - parameter bundles: A list of bundles to search for the source model and intermediate models.
    ///
    /// - Throws: Throws an error, if the necessary steps cannot be determined.
    static func stepsForMigratingExistingStore(withMetadata storeMetadata: [String: Any], to destinationModel: NSManagedObjectModel, searchBundles bundles: [Bundle]) throws -> [MigrationStep] {
        var steps: [MigrationStep] = []
        guard let storeModelVersionHashes = storeMetadata[NSStoreModelVersionHashesKey] as? [String: Any] else {
            throw Error.missingStoreModelVersionHashes
        }
        var latestModelVersionHashes = storeModelVersionHashes
        let models = NSManagedObjectModel.models(in: bundles)
        while !(latestModelVersionHashes as NSDictionary).isEqual(to: destinationModel.entityVersionHashesByName) {
            var stepSourceModel: NSManagedObjectModel!
            for model in models {
                if (model.entityVersionHashesByName as NSDictionary).isEqual(to: latestModelVersionHashes) {
                    stepSourceModel = model
                }
            }
            if stepSourceModel == nil {
                throw Error.couldNotFindSourceModel
            }
            var stepDestinationModel: NSManagedObjectModel!
            var stepMappingModel: NSMappingModel!
            for model in models {
                if let mappingModel = NSMappingModel(from: bundles, forSourceModel: stepSourceModel, destinationModel: model) {
                    stepDestinationModel = model
                    stepMappingModel = mappingModel
                    break
                }
            }
            if stepDestinationModel == nil ||
                stepMappingModel == nil
            {
                throw Error.couldNotInferMappingSteps
            }
            latestModelVersionHashes = stepDestinationModel.entityVersionHashesByName as [String : AnyObject]
            let migrationStep = MigrationStep(sourceModel: stepSourceModel, destinationModel: stepDestinationModel, mappingModel: stepMappingModel)
            steps.append(migrationStep)
        }
        return steps
    }
}
