//
//  PersistentStoreMigrationKitTests.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg C. Brückmann on 26/08/15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData
import XCTest
@testable import PersistentStoreMigrationKit

final class MigrationTests: XCTestCase {

    private var workingDirectoryURL: URL!
    private let storeType = NSSQLiteStoreType
    private var testDataSet: TestDataSet!
    
    override func setUp() {
        super.setUp()

        // Create working directory.
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        workingDirectoryURL = temporaryDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        do {
            try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            XCTFail("Could not create working directory: \(error)")
        }

        // Create test data set
        do {
            let testDataSetURL = workingDirectoryURL.appendingPathComponent("Pristine Data Set", isDirectory: true)
            testDataSet = try TestDataSet(at: testDataSetURL, storeType: storeType)
        } catch {
            XCTFail("Could not create test data set: \(error)")
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
    
    func testManualStoreMigration() {
        let storeURL = workingDirectoryURL.appendingPathComponent("Manually Migrated Store", isDirectory: false)
        do {
            try testDataSet.copyStore(for: .v1, ofType: storeType, to: storeURL)
        } catch {
            XCTFail("Could not initialize persistent store: \(error)")
            return
        }

        for newerModel in TestDataSet.ModelVersion.versions(after: .v1).map({ $0.model }) {
            let existingStoreMetadata: [String: AnyObject]
            do {
                existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
            } catch {
                XCTFail("Could not retrieve store metadata: \(error)")
                return
            }
            guard let existingStoreVersionHashes = existingStoreMetadata[NSStoreModelVersionHashesKey] as? NSDictionary else {
                XCTFail("Could not retrieve version hashes from \(storeURL).")
                return
            }
            var sourceModel: NSManagedObjectModel!
            for model in TestDataSet.ModelVersion.all.map({ $0.model }) {
                if (model.entityVersionHashesByName as NSDictionary).isEqual(to: existingStoreVersionHashes) {
                    sourceModel = model
                    break
                }
            }
            guard sourceModel != nil else {
                XCTFail("Could not determine source model for store migration.")
                return
            }
            print("Source model entity version hashes:")
            for (entityName, versionHash) in existingStoreVersionHashes {
                print("\(entityName): \(versionHash)")
            }
            print("Target model entity version hashes:")
            for (entityName, versionHash) in newerModel.entityVersionHashesByName {
                print("\(entityName): \(versionHash)")
            }
            guard let mappingModel = NSMappingModel(from: [Bundle.test], forSourceModel: sourceModel!, destinationModel: newerModel) else {
                XCTFail("Could not find a model for mapping \(sourceModel) to \(newerModel).")
                return
            }
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
            try testDataSet.copyStore(for: .v1, ofType: storeType, to: storeURL)
        } catch {
            XCTFail("Could not initialize persistent store: \(error)")
            return
        }

        let latestModel = TestDataSet.ModelVersion.latest.model
        let existingStoreMetadata: [String: AnyObject]
        do {
            existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
        } catch {
            XCTFail("Could not retrieve store metadata: \(error)")
            return
        }
        let migrationPlan: MigrationPlan
        do {
            migrationPlan = try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: latestModel, bundles: [Bundle.test])
        } catch {
            XCTFail("Could not devise migration plan for \(storeURL): \(error)")
            return
        }
        let expectedMigrationPlanStepCount = TestDataSet.ModelVersion.all.count - 1
        XCTAssertEqual(migrationPlan.numberOfSteps, expectedMigrationPlanStepCount, "Migration plan step count should be \(expectedMigrationPlanStepCount), but is \(migrationPlan.numberOfSteps).")
        do {
            try migrationPlan.executeForStore(at: storeURL, type: storeType, destinationURL: storeURL, storeType: storeType)
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
            try testDataSet.copyStore(for: .v1, ofType: storeType, to: storeURL)
        } catch {
            XCTFail("Could not initialize persistent store: \(error)")
            return
        }

        let latestModel = TestDataSet.ModelVersion.latest.model

        let operationExpectation = expectation(description: "Migration operation succeeded")
        let operationQueue = OperationQueue()
        operationQueue.name = "Core Data Migration Test"
        let migrationOperation = MigrationOperation()
        migrationOperation.sourceURL = storeURL
        migrationOperation.sourceStoreType = storeType
        migrationOperation.destinationURL = storeURL
        migrationOperation.destinationStoreType = storeType
        migrationOperation.destinationModel = latestModel
        migrationOperation.bundles = [Bundle.test]
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
        let latestModel = TestDataSet.ModelVersion.latest.model
        let existingStoreMetadata: [String: AnyObject]
        do {
            existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL) as [String : AnyObject]
            XCTFail("Retrieving store metadata for nonexistant store succeeded: \(existingStoreMetadata)")
        } catch {
            existingStoreMetadata = [:]
        }
        do {
            let migrationPlan = try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: latestModel, bundles: [Bundle.test])
            XCTFail("Devising migration plan for nonexistant store succeeded: \(migrationPlan)")
        } catch {}
    }
}
