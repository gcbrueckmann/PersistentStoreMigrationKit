//
//  MigrationPlanTests.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg C. Brückmann on 26/08/15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData
import XCTest
@testable import PersistentStoreMigrationKit

final class MigrationPlanTests: XCTestCase {

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

    /// Verifies that a migration plan for A → A migrations does not required execution for store compatibility.
    func testExecutingMigrationFromAToAIsNotRequiredForCompatibility() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v1.model, bundles: [.test])

        XCTAssertFalse(migrationPlan.isExecutionRequiredForStoreCompatibility)
    }

    /// Verifies migration plan execution for A → A migrations.
    func testMigrationFromAToAExecutesSuccessfully() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v1.model, bundles: [.test])

        XCTAssertNoThrow(try migrationPlan.executeForStore(at: pristineStoreInfo.url, type: storeType, destinationURL: migratedStoreURL, storeType: storeType))
        XCTAssertValidStore(at: migratedStoreURL, ofType: storeType, for: TestDataSet.ModelVersion.v1.model)
    }

    /// Verifies migration plan execution for A → B migrations.
    func testMigrationFromAToBExecutesSuccessfully() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v2.model, bundles: [.test])

        XCTAssertNoThrow(try migrationPlan.executeForStore(at: pristineStoreInfo.url, type: storeType, destinationURL: migratedStoreURL, storeType: storeType))
        XCTAssertValidStore(at: migratedStoreURL, ofType: storeType, for: TestDataSet.ModelVersion.v2.model)
    }

    /// Verifies migration plan execution for A → C migrations.
    func testMigrationFromAToCExecutesSuccessfully() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: TestDataSet.ModelVersion.v3.model, bundles: [.test])

        XCTAssertNoThrow(try migrationPlan.executeForStore(at: pristineStoreInfo.url, type: storeType, destinationURL: migratedStoreURL, storeType: storeType))
        XCTAssertValidStore(at: migratedStoreURL, ofType: storeType, for: TestDataSet.ModelVersion.v3.model)
    }
    
    /// Verifies that migration plan execution fails when the source store does not exist.
    func testMigrationFailsWhenSourceStoreDoesNotExist() throws {
        let pristineStoreInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)
        let storeURL = pristineStoreInfo.url.deletingLastPathComponent().appendingPathComponent("Store That Does Not Exist", isDirectory: false)
        let migratedStoreURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let latestModel = TestDataSet.ModelVersion.latestWithMigrationPath.model

        let migrationPlan = try MigrationPlan(storeMetadata: pristineStoreInfo.metadata, destinationModel: latestModel, bundles: [.test])
        XCTAssertThrowsError(try migrationPlan.executeForStore(at: storeURL, type: storeType, destinationURL: migratedStoreURL, storeType: storeType), "Executing a migration plan for a non-existant source store should fail.")
    }
}
