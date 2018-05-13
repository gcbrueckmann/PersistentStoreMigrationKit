//
//  MigrationOperationTests.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg C. Brückmann on 26/08/15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData
import XCTest
@testable import PersistentStoreMigrationKit

final class MigrationOperationTests: XCTestCase {

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

    /// Verifies that migration operations become ready only once they are fully configured.
    func testMigrationOperationBecomesReadyOnceFullyConfigured() {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let latestModel = TestDataSet.ModelVersion.latestWithMigrationPath.model

        let migrationOperation = MigrationOperation()
        XCTAssertFalse(migrationOperation.isReady)

        migrationOperation.sourceURL = pristineStoreInfo.url
        XCTAssertFalse(migrationOperation.isReady)

        migrationOperation.sourceStoreType = storeType
        XCTAssertFalse(migrationOperation.isReady)

        migrationOperation.destinationURL = migratedStoreURL
        XCTAssertFalse(migrationOperation.isReady)

        migrationOperation.destinationStoreType = storeType
        XCTAssertFalse(migrationOperation.isReady)

        migrationOperation.destinationModel = latestModel
        XCTAssertFalse(migrationOperation.isReady)

        migrationOperation.bundles = [.test]
        XCTAssertTrue(migrationOperation.isReady)
    }

    /// Verifies that migration operations execute successfully (when backed by a working migration plan).
    func testMigrationOperationExecutesSuccessfully() {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let latestModel = TestDataSet.ModelVersion.latestWithMigrationPath.model

        let operationExpectation = expectation(description: "Migration operation finishes")
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
            defer { operationExpectation.fulfill() }
            XCTAssertNil(migrationOperation.error, "Migration operation failed: \(migrationOperation.error!)")
        }
        operationQueue.addOperation(migrationOperation)
        waitForExpectations(timeout: 10) { _ in
            XCTAssertValidStore(at: migratedStoreURL, ofType: self.storeType, for: latestModel)
        }
    }

    /// Verifies that migration operations fail when the source store does not exist
    func testMigrationOperationFailsWhenSourceStoreDoesNotExist() {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let storeURL = pristineStoreInfo.url.deletingLastPathComponent().appendingPathComponent("Store That Does Not Exist", isDirectory: false)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let latestModel = TestDataSet.ModelVersion.latestWithMigrationPath.model

        let operationExpectation = expectation(description: "Migration operation finishes")
        let operationQueue = OperationQueue()
        operationQueue.name = "Core Data Migration Test"
        let migrationOperation = MigrationOperation()
        migrationOperation.sourceURL = storeURL
        migrationOperation.sourceStoreType = storeType
        migrationOperation.destinationURL = migratedStoreURL
        migrationOperation.destinationStoreType = storeType
        migrationOperation.destinationModel = latestModel
        migrationOperation.bundles = [.test]
        migrationOperation.completionBlock = {
            defer { operationExpectation.fulfill() }
            XCTAssertNotNil(migrationOperation.error, "Migration operation did not yield an error.")
        }
        operationQueue.addOperation(migrationOperation)
        waitForExpectations(timeout: 10)
    }
}
