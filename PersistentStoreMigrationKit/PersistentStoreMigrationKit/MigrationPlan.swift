//
//  MigrationPlan.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg C. Brückmann on 26.08.15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData

public final class MigrationPlan: NSObject {
	private var steps = [MigrationStep]()
	public var stepCount: Int { return steps.count }
	public var isEmpty: Bool { return stepCount == 0 }
	
	private static func modelsInBundles(bundles: [NSBundle]) -> [NSManagedObjectModel] {
		var models = [NSManagedObjectModel]()
		for bundle in bundles {
			if let modelURLs = bundle.URLsForResourcesWithExtension("mom", subdirectory: nil) as? [NSURL] {
				for modelURL in modelURLs {
					if let model = NSManagedObjectModel(contentsOfURL: modelURL) {
						models.append(model)
					}
				}
			}
			if let modelURLs = bundle.URLsForResourcesWithExtension("momd", subdirectory: nil) as? [NSURL] {
				for modelBundleURL in modelURLs {
					let modelBundle = NSBundle(URL: modelBundleURL)
					if let modelURLs = bundle.URLsForResourcesWithExtension("mom", subdirectory: nil) as? [NSURL] {
						for modelURL in modelURLs {
							if let model = NSManagedObjectModel(contentsOfURL: modelURL) {
								models.append(model)
							}
						}
					}
				}
			}
		}
		return models
	}
	
	public init?(storeMetadata: [NSObject: AnyObject], destinationModel: NSManagedObjectModel, bundles: [NSBundle], inout error: NSError?) {
		precondition(!bundles.isEmpty, "Bundles must be non-empty.")
		if destinationModel.isConfiguration(nil, compatibleWithStoreMetadata: storeMetadata) {
			super.init()
			return
		}
		var latestModelVersionHashes = storeMetadata[NSStoreModelVersionHashesKey] as! [NSObject: AnyObject]!
		precondition(latestModelVersionHashes != nil, "Model version hashes missing from store metadata.")
		let modles = self.dynamicType.modelsInBundles(bundles)
		while !(latestModelVersionHashes as NSDictionary).isEqualToDictionary(destinationModel.entityVersionHashesByName) {
			let migrationStepIndex = steps.count
			var stepSourceModel: NSManagedObjectModel!
			for model in modles {
				if (model.entityVersionHashesByName as NSDictionary).isEqualToDictionary(latestModelVersionHashes) {
					stepSourceModel = model
				}
			}
			if stepSourceModel == nil {
				super.init()
				let localizedErrorDescriptionFormat = NSLocalizedString("Could not find the source model for migration step %lu.", tableName: "PersistentStoreMigrationKit", comment: "Error description when the source model for a migration step cannot be located in the specified bundles.")
				let localizedErrorDescription = NSString.localizedStringWithFormat(localizedErrorDescriptionFormat, migrationStepIndex + 1)
				error = NSError(persistentStoreMigrationKitCode: .CouldNotFindSourceModel, userInfo: [NSLocalizedDescriptionKey: localizedErrorDescription])
				return nil
			}
			var stepDestinationModel: NSManagedObjectModel!
			var stepMappingModel: NSMappingModel!
			for model in modles {
				if let mappingModel = NSMappingModel(fromBundles: bundles, forSourceModel: stepSourceModel, destinationModel: model) {
					stepDestinationModel = model
					stepMappingModel = mappingModel
					break
				}
			}
			if stepDestinationModel == nil ||
				stepMappingModel == nil
			{
				super.init()
				let localizedErrorDescriptionFormat = NSLocalizedString("Could not find a destination and mapping model for migration step %lu.", tableName: "PersistentStoreMigrationKit", comment: "Error description when the destination and mapping model for a migration step cannot be located in the specified bundles.")
				let localizedErrorDescription = NSString.localizedStringWithFormat(localizedErrorDescriptionFormat, migrationStepIndex + 1)
				error = NSError(persistentStoreMigrationKitCode: .CouldNotInferMappingSteps, userInfo: [NSLocalizedDescriptionKey: localizedErrorDescription])
				return nil
			}
			latestModelVersionHashes = stepDestinationModel.entityVersionHashesByName
			let stepMigrationManager = NSMigrationManager(sourceModel: stepSourceModel, destinationModel: stepDestinationModel)
			let migrationStep = MigrationStep(sourceModel: stepSourceModel, destinationModel: stepDestinationModel, mappingModel: stepMappingModel)
			steps.append(migrationStep)
		}
		if steps.isEmpty {
			super.init()
			error = NSError(persistentStoreMigrationKitCode: .CouldNotInferMappingSteps, userInfo: nil)
			return nil
		}
		super.init()
	}
	
	public func executeForStoreAtURL(sourceURL: NSURL, type sourceStoreType: String, destinationURL: NSURL, storeType destinationStoreType: String, inout error: NSError?) -> Bool {
		// 10% setup, 80% actual migration steps, 10% cleanup.
		let overallProgress = NSProgress(totalUnitCount: Int64(steps.count))
		
		// Setup
		var storeReplacementDirectoryError: NSError?
		let storeReplacementDirectory: NSURL! = NSFileManager.defaultManager().URLForDirectory(.ItemReplacementDirectory, inDomain: .UserDomainMask, appropriateForURL: destinationURL, create: true, error: &storeReplacementDirectoryError)
		if storeReplacementDirectory == nil {
			error = storeReplacementDirectoryError
			return false
		}
		overallProgress.completedUnitCount += 10
		
		// Execute migration steps.
		overallProgress.becomeCurrentWithPendingUnitCount(80)
		let steppingProgress = NSProgress(totalUnitCount: Int64(steps.count))
		overallProgress.resignCurrent()
		var latestStoreURL = sourceURL
		var latestStoreType = sourceStoreType
		var storeCopyError: NSError?
		for (stepIndex, step) in enumerate(steps) {
			let stepDestinationURL = storeReplacementDirectory.URLByAppendingPathComponent("Migrated Store (Step \(stepIndex + 1) of \(stepCount))", isDirectory: false)
			var stepError: NSError?
			if !step.executeForStoreAtURL(latestStoreURL, type: latestStoreType, destinationURL: stepDestinationURL, storeType: destinationStoreType, error: &stepError) {
				error = stepError
				NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectory, error: nil)
				return false
			}
			latestStoreURL = stepDestinationURL
			latestStoreType = destinationStoreType
			steppingProgress.completedUnitCount++
		}
		
		// Cleanup
		var storeReplacementError: NSError?
		if !NSFileManager.defaultManager().replaceItemAtURL(destinationURL, withItemAtURL: latestStoreURL, backupItemName: nil, options: .allZeros, resultingItemURL: nil, error: &storeReplacementError) {
			error = storeReplacementError
			NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectory, error: nil)
			return false
		}
		NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectory, error: nil)
		overallProgress.completedUnitCount += 10
		return true
	}
}
