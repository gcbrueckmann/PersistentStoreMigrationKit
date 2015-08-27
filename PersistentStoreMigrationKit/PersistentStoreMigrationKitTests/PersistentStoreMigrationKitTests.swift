//
//  PersistentStoreMigrationKitTests.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg C. Brückmann on 26/08/15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Cocoa
import CoreData
import XCTest
import PersistentStoreMigrationKit

class PersistentStoreMigrationKitTests: XCTestCase {
	private var models = [NSManagedObjectModel]()
	private var workingDirectoryURL: NSURL!
	private let storeType = NSSQLiteStoreType
	private var testBundle: NSBundle!
    
    override func setUp() {
        super.setUp()
		
		testBundle = NSBundle(forClass: self.dynamicType)
		
		let modelVersions = 1...3
		for versionNumber in modelVersions {
			let modelURL: NSURL! = testBundle.URLForResource("TestModelV\(versionNumber)", withExtension: "mom")
			XCTAssertNotNil(modelURL, "Could not locate V\(versionNumber) test model.")
			let model: NSManagedObjectModel! = NSManagedObjectModel(contentsOfURL: modelURL)
			XCTAssertNotNil(model, "Could not load V\(versionNumber) test model.")
			models.append(model)
		}
		
		// Create working directory.
		if let workingDirectoryPath = NSTemporaryDirectory()?.stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString) {
			workingDirectoryURL = NSURL(fileURLWithPath: workingDirectoryPath, isDirectory: true)
		}
		XCTAssertNotNil(workingDirectoryURL, "Could not locate working directory.")
		var workingDirectoryCreationError: NSError?
		XCTAssertTrue(NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil, error: &workingDirectoryCreationError), "Could not create working directory: \(workingDirectoryCreationError)")
    }
    
    override func tearDown() {
		if let workingDirectoryURL = workingDirectoryURL {
			var workingDirectoryRemovalError: NSError?
			XCTAssertTrue(NSFileManager.defaultManager().removeItemAtURL(workingDirectoryURL, error: &workingDirectoryRemovalError), "Could not remove working directory: \(workingDirectoryRemovalError)")
		}
        super.tearDown()
    }
	
	private func initializeStoreAtURL(storeURL: NSURL, inout error: NSError?) -> Bool {
		var persistentStoreError: NSError?
		let initialPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: models.first!)
		let initialPersistentStore = initialPersistentStoreCoordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil, error: &persistentStoreError)
		if initialPersistentStore == nil {
			error = persistentStoreError
			return false
		}
		return true
	}
    
    func testManualStoreMigration() {
		let storeURL = workingDirectoryURL.URLByAppendingPathComponent("Manually Migrated Store", isDirectory: false)
		var storeInitializationError: NSError?
		let storeInitializationSucceeded = initializeStoreAtURL(storeURL, error: &storeInitializationError)
		XCTAssertNotNil(storeInitializationSucceeded, "Could not initialize persistent store: \(storeInitializationError)")
		
		for newerModel in models[1..<models.endIndex] {
			var metadataError: NSError?
			let existingStoreMetadata: [NSObject: AnyObject]! = NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(storeType, URL: storeURL, error: &metadataError)
			XCTAssertNotNil(existingStoreMetadata, "Could not retrieve store metadata: \(metadataError)")
			let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [NSObject: AnyObject]!
			XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
			var sourceModel: NSManagedObjectModel!
			for model in models {
				if (model.entityVersionHashesByName as NSDictionary).isEqualToDictionary(existingStoreVersionHashes) {
					sourceModel = model
					break
				}
			}
			XCTAssertNotNil(sourceModel, "Could not determine source model for store migration.")
			println("Source model entity version hashes:")
			for (entityName, versionHash) in existingStoreVersionHashes {
				println("\(entityName): \(versionHash)")
			}
			println("Target model entity version hashes:")
			for (entityName, versionHash) in newerModel.entityVersionHashesByName {
				println("\(entityName): \(versionHash)")
			}
			let mappingModel: NSMappingModel! = NSMappingModel(fromBundles: [testBundle], forSourceModel: sourceModel!, destinationModel: newerModel)
			XCTAssertNotNil(mappingModel, "Could not find a model for mapping \(sourceModel) to \(newerModel).")
			let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: newerModel)
			var storeReplacementDirectoryError: NSError?
			let storeReplacementDirectoryURL: NSURL! = NSFileManager.defaultManager().URLForDirectory(.ItemReplacementDirectory, inDomain: .UserDomainMask, appropriateForURL: storeURL, create: true, error: &storeReplacementDirectoryError)
			XCTAssertNotNil(storeReplacementDirectoryURL, "Could not create item replacement directory for migrating store: \(storeReplacementDirectoryError)")
			let temporaryStoreURL = storeReplacementDirectoryURL.URLByAppendingPathComponent(storeURL.lastPathComponent!, isDirectory: false)
			var migrationError: NSError?
			let migrationSucceeded = migrationManager.migrateStoreFromURL(storeURL, type: storeType, options: nil, withMappingModel: mappingModel, toDestinationURL: temporaryStoreURL, destinationType: storeType, destinationOptions: nil, error: &migrationError)
			XCTAssertTrue(migrationSucceeded, "Could not migrate \(storeURL) from \(sourceModel) to \(newerModel): \(migrationError)")
			var newStoreURL: NSURL?
			var storeReplacementError: NSError?
			let storeReplacementSucceeded = NSFileManager.defaultManager().replaceItemAtURL(storeURL, withItemAtURL: temporaryStoreURL, backupItemName: nil, options: .allZeros, resultingItemURL: &newStoreURL, error: &storeReplacementError)
			XCTAssertTrue(storeReplacementSucceeded, "Could not replace \(storeURL) with migrated store \(temporaryStoreURL): \(storeReplacementError)")
			var storeReplacementDirectoryRemovalError: NSError?
			let storeReplacementDirectoryRemovalSucceeded = NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectoryURL, error: &storeReplacementDirectoryRemovalError)
			XCTAssertTrue(storeReplacementDirectoryRemovalSucceeded, "Could not remove item replacmeent directory after migrating store: \(storeReplacementDirectoryRemovalError)")
		}
    }
	
	func testAutomaticMigration() {
		let storeURL = workingDirectoryURL.URLByAppendingPathComponent("Automatically Migrated Store", isDirectory: false)
		var storeInitializationError: NSError?
		let storeInitializationSucceeded = initializeStoreAtURL(storeURL, error: &storeInitializationError)
		XCTAssertNotNil(storeInitializationSucceeded, "Could not initialize persistent store: \(storeInitializationError)")
		
		let latestModel = models.last!
		
		var metadataError: NSError?
		let existingStoreMetadata: [NSObject: AnyObject]! = NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(storeType, URL: storeURL, error: &metadataError)
		XCTAssertNotNil(existingStoreMetadata, "Could not retrieve store metadata: \(metadataError)")
		let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [NSObject: AnyObject]!
		XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
		var migrationPlanError: NSError?
		let migrationPlan: MigrationPlan! = MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: latestModel, bundles: [testBundle], error: &migrationPlanError)
		XCTAssertNotNil(migrationPlan, "Could not devise migration plan for \(storeURL): \(migrationPlanError)")
		let expectedMigrationPlanStepCount = models.count - 1
		XCTAssertEqual(migrationPlan.stepCount, expectedMigrationPlanStepCount, "Migration plan step count should be \(expectedMigrationPlanStepCount), but is \(migrationPlan.stepCount).")
		var migrationPlanExecutionError: NSError?
		let migrationSucceeded = migrationPlan.executeForStoreAtURL(storeURL, type: storeType, destinationURL: storeURL, storeType: storeType, error: &migrationPlanExecutionError)
		XCTAssertTrue(migrationSucceeded, "Could not execute migration plan for \(storeURL): \(migrationPlanExecutionError)")
		
		let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
		var persistentStoreError: NSError?
		let persistentStore: NSPersistentStore! = persistentStoreCoordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil, error: &persistentStoreError)
		XCTAssertNotNil(persistentStore, "Could not load persistent store after migration.")
	}
	
	func testMigrationOperation() {
		let storeURL = workingDirectoryURL.URLByAppendingPathComponent("Automatically Migrated Store", isDirectory: false)
		var storeInitializationError: NSError?
		let storeInitializationSucceeded = initializeStoreAtURL(storeURL, error: &storeInitializationError)
		XCTAssertNotNil(storeInitializationSucceeded, "Could not initialize persistent store: \(storeInitializationError)")
		
		let latestModel = models.last!
		
		var metadataError: NSError?
		let existingStoreMetadata: [NSObject: AnyObject]! = NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(storeType, URL: storeURL, error: &metadataError)
		XCTAssertNotNil(existingStoreMetadata, "Could not retrieve store metadata: \(metadataError)")
		let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [NSObject: AnyObject]!
		XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
		
		let operationQueue = NSOperationQueue()
		operationQueue.name = "Core Data Migration Test"
		let migrationOperation = MigrationOperation()
		migrationOperation.sourceURL = storeURL
		migrationOperation.sourceStoreType = storeType
		migrationOperation.destinationURL = storeURL
		migrationOperation.destinationStoreType = storeType
		migrationOperation.destinationModel = latestModel
		migrationOperation.bundles = [testBundle]
		operationQueue.addOperation(migrationOperation)
		operationQueue.waitUntilAllOperationsAreFinished()
		XCTAssertNil(migrationOperation.error, "Migration operation failed: \(migrationOperation.error)")
		
		let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
		var persistentStoreError: NSError?
		let persistentStore: NSPersistentStore! = persistentStoreCoordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil, error: &persistentStoreError)
		XCTAssertNotNil(persistentStore, "Could not load persistent store after migration.")
	}
}
