//
//  MigrationPlan.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg C. Brückmann on 26.08.15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData

/// A `MigrationPlan` instance encapsulates the progressive migration from one `NSManagedObjectModel` to another with an arbitrary number of intermediate models.
@objc public final class MigrationPlan: NSObject {
    private let steps: [MigrationStep]
    /// The number of steps in the plan. Zero, if the plan is empty.
    @objc public var numberOfSteps: Int { return steps.count }
    /// Indicates whether executing the plan will do nothing.
    @objc public var isEmpty: Bool { return numberOfSteps == 0 }
    
    /// Devises a migration plan based on the metadata of an existing store, a destination managed object model and a list of bundles to search for intermediate models.
    /// 
    /// If no migration is necessary (i.e. the existing store's metadata is compatible with the destination model), the initialized plan will be empty.
    /// 
    /// - Throws: Throws an error if a migration plan cannot be devised.
    /// 
    /// - Parameters:
    ///   - storeMetadata: The metadata of an existing persistent store.
    ///   - destinationModel: The model to migrate to.
    ///   - bundles: A list of bundles to search for the source model and intermediate models.
    @objc public init(storeMetadata: [String: Any], destinationModel: NSManagedObjectModel, bundles: [Bundle]) throws {
        precondition(!bundles.isEmpty, "Bundles must be non-empty.")
        let _ = Progress(totalUnitCount: -1)
        guard !destinationModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: storeMetadata) else {
            // No work to be done.
            self.steps = []
            super.init()
            return
        }
        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeMetadata, to: destinationModel, searchBundles: bundles)
        guard !steps.isEmpty else {
            throw Error.couldNotInferMappingSteps
        }
        self.steps = steps
        super.init()
    }
    
    /// Performs the migration from the persistent store identified by `sourceURL` to `destinationModel`, saving the result in the persistent store identified by `destinationURL`.
    /// The migration is guaranteed to be atomic.
    /// 
    /// Inserts an `NSProgress` instance into the current progress tree.
    /// 
    /// - Parameters:
    ///   - sourceURL: Identifies the persistent store to migrate from.
    ///   - sourceStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the source store type.
    ///   - destinationURL: Identifies the persistent store to migrate to. May be identical to `sourceURL`.
    ///   - destinationStoreType: A string constant (such as `NSSQLiteStoreType`) that specifies the destination store type.
    @objc public func executeForStoreAtURL(_ sourceURL: URL, type sourceStoreType: String, destinationURL: URL, storeType destinationStoreType: String) throws {
        guard !isEmpty else { return }

        // 10% setup, 80% actual migration steps, 10% cleanup.
        let overallProgress = Progress(totalUnitCount: 100)
        
        // Setup
        let storeReplacementDirectory: URL!
        storeReplacementDirectory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destinationURL, create: true)
        overallProgress.completedUnitCount += 10
        
        // Execute migration steps.
        overallProgress.becomeCurrent(withPendingUnitCount: 80)
        let steppingProgress = Progress(totalUnitCount: Int64(steps.count))
        overallProgress.resignCurrent()
        var latestStoreURL = sourceURL
        var latestStoreType = sourceStoreType
        for (stepIndex, step) in steps.enumerated() {
            let stepDestinationURL = storeReplacementDirectory.appendingPathComponent("Migrated Store (Step \(stepIndex + 1) of \(numberOfSteps))", isDirectory: false)
            var stepError: Swift.Error?
            do {
                steppingProgress.becomeCurrent(withPendingUnitCount: 1)
                defer { steppingProgress.resignCurrent() }
                try step.executeForStoreAtURL(latestStoreURL, type: latestStoreType, destinationURL: stepDestinationURL, storeType: destinationStoreType)
            } catch {
                let _ = try? FileManager.default.removeItem(at: storeReplacementDirectory)
                throw error
            }
            latestStoreURL = stepDestinationURL
            latestStoreType = destinationStoreType
        }
        
        // Cleanup
        do {
            try FileManager.default.replaceItem(at: destinationURL, withItemAt: latestStoreURL, backupItemName: nil, options: [], resultingItemURL: nil)
        } catch {
            let _ = try? FileManager.default.removeItem(at: storeReplacementDirectory)
            throw error
        }
        let _ = try? FileManager.default.removeItem(at: storeReplacementDirectory)
        overallProgress.completedUnitCount += 10
    }
}
