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
			if let modelURLs = bundle.URLsForResourcesWithExtension("mom", subdirectory: nil) {
				for modelURL in modelURLs {
					if let model = NSManagedObjectModel(contentsOfURL: modelURL) {
						models.append(model)
					}
				}
			}
			if let modelURLs = bundle.URLsForResourcesWithExtension("momd", subdirectory: nil) {
				for modelBundleURL in modelURLs {
					if let modelBundle = NSBundle(URL: modelBundleURL),
						modelURLs = modelBundle.URLsForResourcesWithExtension("mom", subdirectory: nil)
					{
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
	
	public init(storeMetadata: [String: AnyObject], destinationModel: NSManagedObjectModel, bundles: [NSBundle]) throws {
		precondition(!bundles.isEmpty, "Bundles must be non-empty.")
		let _ = NSProgress(totalUnitCount: -1)
		if destinationModel.isConfiguration(nil, compatibleWithStoreMetadata: storeMetadata) {
			super.init()
			return
		}
		guard let storeModelVersionHashes = storeMetadata[NSStoreModelVersionHashesKey] as? [String: AnyObject] else {
			super.init()
			let localizedErrorDescription = NSLocalizedString("Model version hashes are missing from store metadata.", tableName: "PersistentStoreMigrationKit", comment: "Error description when the store metadata does not contain version hashes for the model used to create it.")
			throw NSError(persistentStoreMigrationKitCode: .MissingStoreModelVersionHashes, userInfo: [NSLocalizedDescriptionKey: localizedErrorDescription])
		}
		var latestModelVersionHashes = storeModelVersionHashes
		let models = self.dynamicType.modelsInBundles(bundles)
		while !(latestModelVersionHashes as NSDictionary).isEqualToDictionary(destinationModel.entityVersionHashesByName) {
			let migrationStepIndex = steps.count
			var stepSourceModel: NSManagedObjectModel!
			for model in models {
				if (model.entityVersionHashesByName as NSDictionary).isEqualToDictionary(latestModelVersionHashes) {
					stepSourceModel = model
				}
			}
			if stepSourceModel == nil {
				super.init()
				let localizedErrorDescriptionFormat = NSLocalizedString("Could not find the source model for migration step %lu.", tableName: "PersistentStoreMigrationKit", comment: "Error description when the source model for a migration step cannot be located in the specified bundles.")
				let localizedErrorDescription = NSString.localizedStringWithFormat(localizedErrorDescriptionFormat, migrationStepIndex + 1)
				throw NSError(persistentStoreMigrationKitCode: .CouldNotFindSourceModel, userInfo: [NSLocalizedDescriptionKey: localizedErrorDescription])
			}
			var stepDestinationModel: NSManagedObjectModel!
			var stepMappingModel: NSMappingModel!
			for model in models {
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
				throw NSError(persistentStoreMigrationKitCode: .CouldNotInferMappingSteps, userInfo: [NSLocalizedDescriptionKey: localizedErrorDescription])
			}
			latestModelVersionHashes = stepDestinationModel.entityVersionHashesByName
			let migrationStep = MigrationStep(sourceModel: stepSourceModel, destinationModel: stepDestinationModel, mappingModel: stepMappingModel)
			steps.append(migrationStep)
		}
		if steps.isEmpty {
			super.init()
			throw NSError(persistentStoreMigrationKitCode: .CouldNotInferMappingSteps, userInfo: nil)
		}
		super.init()
	}
	
	public func executeForStoreAtURL(sourceURL: NSURL, type sourceStoreType: String, destinationURL: NSURL, storeType destinationStoreType: String) throws {
		var error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
		if isEmpty {
			return
		}
		// 10% setup, 80% actual migration steps, 10% cleanup.
		let overallProgress = NSProgress(totalUnitCount: 100)
		
		// Setup
		var storeReplacementDirectoryError: NSError?
		let storeReplacementDirectory: NSURL!
		do {
			storeReplacementDirectory = try NSFileManager.defaultManager().URLForDirectory(.ItemReplacementDirectory, inDomain: .UserDomainMask, appropriateForURL: destinationURL, create: true)
		} catch let error as NSError {
			storeReplacementDirectoryError = error
			storeReplacementDirectory = nil
		}
		if storeReplacementDirectory == nil {
			throw storeReplacementDirectoryError!
		}
		overallProgress.completedUnitCount += 10
		
		// Execute migration steps.
		overallProgress.becomeCurrentWithPendingUnitCount(80)
		let steppingProgress = NSProgress(totalUnitCount: Int64(steps.count))
		overallProgress.resignCurrent()
		var latestStoreURL = sourceURL
		var latestStoreType = sourceStoreType
		for (stepIndex, step) in steps.enumerate() {
			let stepDestinationURL = storeReplacementDirectory.URLByAppendingPathComponent("Migrated Store (Step \(stepIndex + 1) of \(stepCount))", isDirectory: false)
			var stepError: ErrorType?
			do {
				steppingProgress.becomeCurrentWithPendingUnitCount(1)
				defer { steppingProgress.resignCurrent() }
				try step.executeForStoreAtURL(latestStoreURL, type: latestStoreType, destinationURL: stepDestinationURL, storeType: destinationStoreType)
			} catch {
				let _ = try? NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectory)
				throw error
			}
			latestStoreURL = stepDestinationURL
			latestStoreType = destinationStoreType
		}
		
		// Cleanup
		do {
			try NSFileManager.defaultManager().replaceItemAtURL(destinationURL, withItemAtURL: latestStoreURL, backupItemName: nil, options: [], resultingItemURL: nil)
		} catch let storeReplacementError as NSError {
			let _ = try? NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectory)
			throw storeReplacementError
		}
		let _ = try? NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectory)
		overallProgress.completedUnitCount += 10
	}
}
