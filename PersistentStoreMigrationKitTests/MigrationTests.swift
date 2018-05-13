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

    func testAToAYieldsNoSteps() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v1.model, searchBundles: [.test])

        XCTAssertTrue(steps.isEmpty)
    }

    func testAToBYieldsOneStep() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v2.model, searchBundles: [.test])

        XCTAssertEqual(steps.count, 1)
    }

    func testAToCYieldsTwoSteps() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v3.model, searchBundles: [.test])

        XCTAssertEqual(steps.count, 2)
    }

    func testAToUnsupportedDThrows() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        XCTAssertThrowsError(try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v4.model, searchBundles: [.test]))
    }

    func testAToAExecutesSuccessfully() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v1.model, bundles: [.test])

        XCTAssertNoThrow(try migrationPlan.executeForStore(at: pristineStoreInfo.url, type: storeType, destinationURL: migratedStoreURL, storeType: storeType))
        XCTAssertFalse(FileManager.default.fileExists(atPath: migratedStoreURL.path))
    }

    func testAToBExecutesSuccessfully() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v2.model, bundles: [.test])

        XCTAssertNoThrow(try migrationPlan.executeForStore(at: pristineStoreInfo.url, type: storeType, destinationURL: migratedStoreURL, storeType: storeType))
        XCTAssertValidStore(at: migratedStoreURL, ofType: storeType, for: TestDataSet.ModelVersion.v2.model)
    }

    func testAToCExecutesSuccessfully() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v3.model, bundles: [.test])

        XCTAssertNoThrow(try migrationPlan.executeForStore(at: pristineStoreInfo.url, type: storeType, destinationURL: migratedStoreURL, storeType: storeType))
        XCTAssertValidStore(at: migratedStoreURL, ofType: storeType, for: TestDataSet.ModelVersion.v3.model)
    }
    
    func testMigrationFailsWhenSourceStoreDoesNotExist() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let storeURL = pristineStoreInfo.url.deletingLastPathComponent().appendingPathComponent("Store That Does Not Exist", isDirectory: false)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let latestModel = TestDataSet.ModelVersion.latestWithMigrationPath.model

        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: latestModel, bundles: [.test])
        XCTAssertThrowsError(try migrationPlan.executeForStore(at: storeURL, type: storeType, destinationURL: migratedStoreURL, storeType: storeType), "Executing a migration plan for a non-existant source store should fail.")
    }

    func testMigrationOperationExecutesSuccessfully() {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let latestModel = TestDataSet.ModelVersion.latestWithMigrationPath.model

        let operationExpectation = expectation(description: "Migration operation executes successfully")
        let operationQueue = OperationQueue()
        operationQueue.name = "Core Data Migration Test"
        let migrationOperation = MigrationOperation()
        migrationOperation.sourceURL = pristineStoreInfo.url
        migrationOperation.sourceStoreType = storeType
        migrationOperation.destinationURL = migratedStoreURL
        migrationOperation.destinationStoreType = storeType
        migrationOperation.destinationModel = latestModel
        migrationOperation.bundles = [.test]
        migrationOperation.completionBlock = {
            XCTAssertNil(migrationOperation.error, "Migration operation failed: \(migrationOperation.error!)")
            operationExpectation.fulfill()
        }
        operationQueue.addOperation(migrationOperation)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
            XCTAssertValidStore(at: migratedStoreURL, ofType: self.storeType, for: latestModel)
        }
    }
}

/// Verifies that a persistent store can be openened given a specific managed object model.
private func XCTAssertValidStore(at storeURL: URL, ofType storeType: String, for model: NSManagedObjectModel, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    do {
        try persistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: [NSReadOnlyPersistentStoreOption: true])
    } catch {
        XCTFail("Persistent store at \(storeURL) is not compatible with model (\(model)) - \(message())", file: file, line: line)
    }
}
