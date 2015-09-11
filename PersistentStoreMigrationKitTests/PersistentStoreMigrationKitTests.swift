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
		let temporaryDirectoryURL = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
		workingDirectoryURL = temporaryDirectoryURL.URLByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
		do {
			try NSFileManager.defaultManager().createDirectoryAtURL(workingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
		} catch let error as NSError {
			XCTFail("Could not create working directory: \(error)")
		}
    }
    
    override func tearDown() {
		if let workingDirectoryURL = workingDirectoryURL {
			do {
				try NSFileManager.defaultManager().removeItemAtURL(workingDirectoryURL)
			} catch let error as NSError {
				XCTFail("Could not remove working directory: \(error)")
			}
		}
        super.tearDown()
    }
	
	private func initializeStoreAtURL(storeURL: NSURL) throws {
		let initialPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: models.first!)
		let _ = try initialPersistentStoreCoordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
	}
    
    func testManualStoreMigration() throws {
		let storeURL = workingDirectoryURL.URLByAppendingPathComponent("Manually Migrated Store", isDirectory: false)
		do {
			try initializeStoreAtURL(storeURL)
		} catch let error as NSError {
			XCTFail("Could not initialize persistent store: \(error)")
			throw error
		}
		
		for newerModel in models[1..<models.endIndex] {
			let existingStoreMetadata: [String: AnyObject]
			do {
				existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(storeType, URL: storeURL)
			} catch let error as NSError {
				XCTFail("Could not retrieve store metadata: \(error)")
				throw error
			}
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
			print("Source model entity version hashes:")
			for (entityName, versionHash) in existingStoreVersionHashes {
				print("\(entityName): \(versionHash)")
			}
			print("Target model entity version hashes:")
			for (entityName, versionHash) in newerModel.entityVersionHashesByName {
				print("\(entityName): \(versionHash)")
			}
			let mappingModel: NSMappingModel! = NSMappingModel(fromBundles: [testBundle], forSourceModel: sourceModel!, destinationModel: newerModel)
			XCTAssertNotNil(mappingModel, "Could not find a model for mapping \(sourceModel) to \(newerModel).")
			let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: newerModel)
			let storeReplacementDirectoryURL: NSURL
			do {
				storeReplacementDirectoryURL = try NSFileManager.defaultManager().URLForDirectory(.ItemReplacementDirectory, inDomain: .UserDomainMask, appropriateForURL: storeURL, create: true)
			} catch let error as NSError {
				XCTFail("Could not create item replacement directory for migrating store: \(error)")
				throw error
			}
			let temporaryStoreURL = storeReplacementDirectoryURL.URLByAppendingPathComponent(storeURL.lastPathComponent!, isDirectory: false)
			do {
				try migrationManager.migrateStoreFromURL(storeURL, type: storeType, options: nil, withMappingModel: mappingModel, toDestinationURL: temporaryStoreURL, destinationType: storeType, destinationOptions: nil)
			} catch let error as NSError {
				XCTFail("Could not migrate \(storeURL) from \(sourceModel) to \(newerModel): \(error)")
				throw error
			}
			var newStoreURL: NSURL?
			do {
				try NSFileManager.defaultManager().replaceItemAtURL(storeURL, withItemAtURL: temporaryStoreURL, backupItemName: nil, options: [], resultingItemURL: &newStoreURL)
			} catch let error as NSError {
				XCTFail("Could not replace \(storeURL) with migrated store \(temporaryStoreURL): \(error)")
				throw error
			}
			do {
				try NSFileManager.defaultManager().removeItemAtURL(storeReplacementDirectoryURL)
			} catch let error as NSError {
				XCTFail("Could not remove item replacmeent directory after migrating store: \(error)")
				throw error
			}
		}
    }
	
	func testAutomaticMigration() throws {
		let storeURL = workingDirectoryURL.URLByAppendingPathComponent("Automatically Migrated Store", isDirectory: false)
		do {
			try initializeStoreAtURL(storeURL)
		} catch let error as NSError {
			XCTFail("Could not initialize persistent store: \(error)")
		}
		
		let latestModel = models.last!
		let existingStoreMetadata: [String: AnyObject]
		do {
			existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(storeType, URL: storeURL)
		} catch let error as NSError {
			XCTFail("Could not retrieve store metadata: \(error)")
			throw error
		}
		let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [String: AnyObject]!
		XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
		let migrationPlan: MigrationPlan
		do {
			migrationPlan = try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: latestModel, bundles: [testBundle])
		} catch let error as NSError {
			XCTFail("Could not devise migration plan for \(storeURL): \(error)")
			throw error
		}
		let expectedMigrationPlanStepCount = models.count - 1
		XCTAssertEqual(migrationPlan.stepCount, expectedMigrationPlanStepCount, "Migration plan step count should be \(expectedMigrationPlanStepCount), but is \(migrationPlan.stepCount).")
		do {
			try migrationPlan.executeForStoreAtURL(storeURL, type: storeType, destinationURL: storeURL, storeType: storeType)
		} catch let error as NSError {
			XCTFail("Could not execute migration plan for \(storeURL): \(error)")
			throw error
		}
		let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
		do {
			let _ = try persistentStoreCoordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
		} catch let error as NSError {
			XCTFail("Could not load persistent store after migration: \(error)")
			throw error
		}
	}
	
	func testMigrationOperation() throws {
		let storeURL = workingDirectoryURL.URLByAppendingPathComponent("Automatically Migrated Store", isDirectory: false)
		do {
			try initializeStoreAtURL(storeURL)
		} catch let error as NSError {
			XCTFail("Could not initialize persistent store: \(error)")
			throw error
		}
		
		let latestModel = models.last!
		let existingStoreMetadata: [String: AnyObject]
		do {
			existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(storeType, URL: storeURL)
		} catch let error as NSError {
			XCTFail("Could not retrieve store metadata: \(error)")
			throw error
		}
		let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [String: AnyObject]!
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
		do {
			let _ = try persistentStoreCoordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
		} catch let error as NSError {
			XCTFail("Could not load persistent store after migration: \(error)")
			throw error
		}
	}
}
