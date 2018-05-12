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
@testable import PersistentStoreMigrationKit

class PersistentStoreMigrationKitTests: XCTestCase {
	fileprivate var models = [NSManagedObjectModel]()
	fileprivate var workingDirectoryURL: URL!
	fileprivate let storeType = NSSQLiteStoreType
	fileprivate var testBundle: Bundle!
    
    override func setUp() {
        super.setUp()
		testBundle = Bundle(for: type(of: self))
		
		for versionNumber in 1...3 {
			let modelURL: URL! = testBundle.url(forResource: "TestModelV\(versionNumber)", withExtension: "mom")
			XCTAssertNotNil(modelURL, "Could not locate V\(versionNumber) test model.")
			let model: NSManagedObjectModel! = NSManagedObjectModel(contentsOf: modelURL)
			XCTAssertNotNil(model, "Could not load V\(versionNumber) test model.")
			models.append(model)
		}
		
		// Create working directory.
		let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
		workingDirectoryURL = temporaryDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
		do {
			try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
		} catch {
			XCTFail("Could not create working directory: \(error)")
		}
    }
    
    override func tearDown() {
		if let workingDirectoryURL = workingDirectoryURL {
			do {
				try FileManager.default.removeItem(at: workingDirectoryURL)
			} catch {
				XCTFail("Could not remove working directory: \(error)")
			}
		}
        super.tearDown()
    }
	
	fileprivate func initializeStoreAtURL(_ storeURL: URL) throws {
		let initialPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: models.first!)
		try initialPersistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
	}
    
    func testManualStoreMigration() {
		let storeURL = workingDirectoryURL.appendingPathComponent("Manually Migrated Store", isDirectory: false)
		do {
			try initializeStoreAtURL(storeURL)
		} catch {
			XCTFail("Could not initialize persistent store: \(error)")
			return
		}
		
		for newerModel in models[models.indices.suffix(from: 1)] {
			let existingStoreMetadata: [String: AnyObject]
			do {
				existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
			} catch {
				XCTFail("Could not retrieve store metadata: \(error)")
				return
			}
			let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [AnyHashable: Any]!
			XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
			var sourceModel: NSManagedObjectModel!
			for model in models {
				if (model.entityVersionHashesByName as NSDictionary).isEqual(to: existingStoreVersionHashes) {
					sourceModel = model
					break
				}
			}
			XCTAssertNotNil(sourceModel, "Could not determine source model for store migration.")
			print("Source model entity version hashes:")
			for (entityName, versionHash) in existingStoreVersionHashes! {
				print("\(entityName): \(versionHash)")
			}
			print("Target model entity version hashes:")
			for (entityName, versionHash) in newerModel.entityVersionHashesByName {
				print("\(entityName): \(versionHash)")
			}
			let mappingModel: NSMappingModel! = NSMappingModel(from: [testBundle], forSourceModel: sourceModel!, destinationModel: newerModel)
			XCTAssertNotNil(mappingModel, "Could not find a model for mapping \(sourceModel) to \(newerModel).")
			let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: newerModel)
			let storeReplacementDirectoryURL: URL
			do {
				storeReplacementDirectoryURL = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: storeURL, create: true)
			} catch {
				XCTFail("Could not create item replacement directory for migrating store: \(error)")
				return
			}
			let temporaryStoreURL = storeReplacementDirectoryURL.appendingPathComponent(storeURL.lastPathComponent, isDirectory: false)
			do {
				try migrationManager.migrateStore(from: storeURL, sourceType: storeType, options: nil, with: mappingModel, toDestinationURL: temporaryStoreURL, destinationType: storeType, destinationOptions: nil)
			} catch {
				XCTFail("Could not migrate \(storeURL) from \(sourceModel) to \(newerModel): \(error)")
				return
			}
			do {
                try FileManager.default.replaceItem(at: storeURL, withItemAt: temporaryStoreURL, backupItemName: nil, options: [], resultingItemURL: nil)
			} catch {
				XCTFail("Could not replace \(storeURL) with migrated store \(temporaryStoreURL): \(error)")
				return
			}
			do {
				try FileManager.default.removeItem(at: storeReplacementDirectoryURL)
			} catch {
				XCTFail("Could not remove item replacmeent directory after migrating store: \(error)")
				return
			}
		}
    }
	
	func testAutomaticMigration() {
		let storeURL = workingDirectoryURL.appendingPathComponent("Automatically Migrated Store", isDirectory: false)
		do {
			try initializeStoreAtURL(storeURL)
		} catch {
			XCTFail("Could not initialize persistent store: \(error)")
			return
		}
		
		let latestModel = models.last!
		let existingStoreMetadata: [String: AnyObject]
		do {
			existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
		} catch {
			XCTFail("Could not retrieve store metadata: \(error)")
			return
		}
		let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [String: AnyObject]!
		XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
		let migrationPlan: MigrationPlan
		do {
			migrationPlan = try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: latestModel, bundles: [testBundle])
		} catch {
			XCTFail("Could not devise migration plan for \(storeURL): \(error)")
			return
		}
		let expectedMigrationPlanStepCount = models.count - 1
		XCTAssertEqual(migrationPlan.stepCount, expectedMigrationPlanStepCount, "Migration plan step count should be \(expectedMigrationPlanStepCount), but is \(migrationPlan.stepCount).")
		do {
			try migrationPlan.executeForStoreAtURL(storeURL, type: storeType, destinationURL: storeURL, storeType: storeType)
		} catch {
			XCTFail("Could not execute migration plan for \(storeURL): \(error)")
			return
		}
		let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
		do {
			let _ = try persistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
		} catch {
			XCTFail("Could not load persistent store after migration: \(error)")
			return
		}
	}
	
	func testMigrationOperation() {
		let storeURL = workingDirectoryURL.appendingPathComponent("Automatically Migrated Store", isDirectory: false)
		do {
			try initializeStoreAtURL(storeURL)
		} catch {
			XCTFail("Could not initialize persistent store: \(error)")
			return
		}
		
		let latestModel = models.last!
		let existingStoreMetadata: [String: AnyObject]
		do {
			existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
		} catch {
			XCTFail("Could not retrieve store metadata: \(error)")
			return
		}
		let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as! [String: AnyObject]!
		XCTAssertNotNil(existingStoreVersionHashes, "Could not retrieve version hashes from \(storeURL).")
		
		let operationExpectation = expectation(description: "Migration operation succeeded")
		let operationQueue = OperationQueue()
		operationQueue.name = "Core Data Migration Test"
		let migrationOperation = MigrationOperation()
		migrationOperation.sourceURL = storeURL
		migrationOperation.sourceStoreType = storeType
		migrationOperation.destinationURL = storeURL
		migrationOperation.destinationStoreType = storeType
		migrationOperation.destinationModel = latestModel
		migrationOperation.bundles = [testBundle]
		migrationOperation.completionBlock = {
			XCTAssertNil(migrationOperation.error, "Migration operation failed: \(migrationOperation.error!)")
			operationExpectation.fulfill()
		}
		operationQueue.addOperation(migrationOperation)
		waitForExpectations(timeout: 10) { error in
			if error != nil {
				return
			}
			let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
			do {
				try persistentStoreCoordinator.addPersistentStore(ofType: self.storeType, configurationName: nil, at: storeURL, options: nil)
			} catch {
				XCTFail("Could not load persistent store after migration: \(error)")
				return
			}
		}
	}
	
	func testMigrationFailure() {
		let storeURL = workingDirectoryURL.appendingPathComponent("Store That Does Not Exist", isDirectory: false)
		let latestModel = models.last!
		let existingStoreMetadata: [String: AnyObject]
		do {
			existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
			XCTFail("Retrieving store metadata for nonexistant store succeeded: \(existingStoreMetadata)")
		} catch {
			existingStoreMetadata = [:]
		}
		do {
			let migrationPlan = try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: latestModel, bundles: [testBundle])
			XCTFail("Devising migration plan for nonexistant store succeeded: \(migrationPlan)")
		} catch {}
	}
}
