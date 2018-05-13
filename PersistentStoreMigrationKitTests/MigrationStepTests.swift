//
//  MigrationStepTests.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg C. Brückmann on 26/08/15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData
import XCTest
@testable import PersistentStoreMigrationKit

final class MigrationStepTests: XCTestCase {

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

    /// Verifies step aggregation for A → A migrations.
    func testAToAYieldsNoSteps() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v1.model, searchBundles: [.test])

        XCTAssertTrue(steps.isEmpty)
    }

    /// Verifies step aggregation for A → B migrations.
    func testAToBYieldsOneStep() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v2.model, searchBundles: [.test])

        XCTAssertEqual(steps.count, 1)
    }

    /// Verifies step aggregation for A → C migrations.
    func testAToCYieldsTwoSteps() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        let steps = try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v3.model, searchBundles: [.test])

        XCTAssertEqual(steps.count, 2)
    }

    /// Verifies step aggregation for A → †D migrations (where there is no known migration path from, e.g., C to D).
    func testAToUnsupportedDThrows() throws {
        let storeInfo = testDataSet.infoForPristineStore(for: .v1, ofType: storeType)

        XCTAssertThrowsError(try MigrationStep.stepsForMigratingExistingStore(withMetadata: storeInfo.metadata, to: TestDataSet.ModelVersion.v4.model, searchBundles: [.test]))
    }
}
