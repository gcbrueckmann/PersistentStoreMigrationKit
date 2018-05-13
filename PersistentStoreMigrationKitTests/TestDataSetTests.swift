//
//  TestDataSetTests.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg Brückmann on 13.05.18.
//  Copyright © 2018 Georg C. Brückmann. All rights reserved.
//

import Foundation
import XCTest

final class TestDataSetTests: XCTestCase {

    private var workingDirectoryURL: URL!
    private let storeType = NSSQLiteStoreType

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

    func testLaterVersionsAreIdentifiedCorrectly() {
        XCTAssertEqual(TestDataSet.ModelVersion.versions(after: .v1), [.v2, .v3, .v4])
        XCTAssertEqual(TestDataSet.ModelVersion.versions(after: .v2), [.v3, .v4])
        XCTAssertEqual(TestDataSet.ModelVersion.versions(after: .v3), [.v4])
        XCTAssertEqual(TestDataSet.ModelVersion.versions(after: .v4), [])
    }

    func testDataSetIsCreatedSuccessfully() throws {
        let dataSetURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let dataSet = try TestDataSet(at: dataSetURL, storeType: storeType)
        XCTAssertEqual(dataSet.modelVersions, TestDataSet.ModelVersion.all(), "Data set should contain all model versions.")
    }

    func testDataSetCopiesStoresSuccessfully() throws {
        let dataSetURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let dataSet = try TestDataSet(at: dataSetURL, storeType: storeType)

        for modelVersion in dataSet.modelVersions {
            let storeCopyURL = workingDirectoryURL.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
            try dataSet.copyStore(for: modelVersion, ofType: storeType, to: storeCopyURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: storeCopyURL.path), "File should exist at copy location after making a copy of the \(modelVersion) store.")
        }
    }
}
