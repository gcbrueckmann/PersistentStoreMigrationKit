//
//  TestDataSet.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg Brückmann on 12.05.18.
//  Copyright © 2018 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData

final class TestDataSet {

    private let containerDirectoryURL: URL
    private let storeURLs: [ModelVersion: URL]
    let modelVersions: [ModelVersion]

    init(at url: URL, storeType: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
        self.containerDirectoryURL = url

        // Create stores for all model versions
        self.modelVersions = ModelVersion.all()
        let stores = try modelVersions.map { (modelVersion) -> URL in
            let storeURL = url.appendingPathComponent("PristineStore-\(modelVersion.identifier)")
            try TestDataSet.createStore(at: storeURL, type: storeType, using: modelVersion)

            return storeURL
        }
        storeURLs = Dictionary(uniqueKeysWithValues: zip(modelVersions, stores))
    }

    func infoForPristineStore(for modelVersion: ModelVersion, ofType storeType: String) -> PersistentStoreInfo {
        let storeURL = pristineStoreURL(for: modelVersion)
        let storeMetadata: [String: Any]
        do {
            storeMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: storeURL)
        } catch {
            preconditionFailure("Could not retrieve store metadata: \(error)")
        }
        
        return PersistentStoreInfo(url: storeURL, metadata: storeMetadata)
    }

    struct PersistentStoreInfo {

        let url: URL
        let metadata: [String: Any]
    }

    func copyStore(for modelVersion: ModelVersion, ofType storeType: String, to destinationURL: URL) throws {
        let pristineStoreURL = self.pristineStoreURL(for: modelVersion)
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: modelVersion.model)
        let pristinePersistentStore = try persistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: pristineStoreURL, options: nil)
        try persistentStoreCoordinator.migratePersistentStore(pristinePersistentStore, to: destinationURL, options: nil, withType: storeType)
    }

    /// Returns a URL identifying a pristine copy for a given model version.
    /// You should treat the store at the returned URL as read-only.
    private func pristineStoreURL(for modelVersion: ModelVersion) -> URL {
        guard let storeURL = storeURLs[modelVersion] else {
            preconditionFailure("There is no store for model version \(modelVersion) even though we should have created one for every version.")
        }
        return storeURL
    }

    private static func createStore(at storeURL: URL, type storeType: String, using modelVersion: ModelVersion) throws {
        let initialPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: modelVersion.model)
        try initialPersistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
    }
}

extension TestDataSet {

    struct ModelVersion: CustomStringConvertible, Hashable {

        private let versionCounter: Int
        let model: NSManagedObjectModel

        var identifier: String { return "V\(versionCounter)" }

        private init(versionCounter: Int) {
            self.versionCounter = versionCounter

            guard let modelURL = Bundle.test.url(forResource: "TestModelV\(versionCounter)", withExtension: "mom") else {
                preconditionFailure("Could not locate test model V\(versionCounter).")
            }
            guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
                preconditionFailure("Could not load test model V\(versionCounter).")
            }
            self.model = model
        }

        var description: String {
            return "V\(versionCounter)"
        }

        static func ==(_ lhs: ModelVersion, _ rhs: ModelVersion) -> Bool {
            return lhs.versionCounter == rhs.versionCounter
        }

        var hashValue: Int {
            return versionCounter
        }

        static let v1 = ModelVersion(versionCounter: 1)
        static let v2 = ModelVersion(versionCounter: 2)
        static let v3 = ModelVersion(versionCounter: 3)
        static let v4 = ModelVersion(versionCounter: 4)

        static func all(supportingMigrationOnly: Bool = false) -> [ModelVersion] {
            let versionsSupportingMigration: [ModelVersion] = [
                .v1,
                .v2,
                .v3
            ]
            let versionsNotSupportingMigration: [ModelVersion] = [
                .v4
            ]

            if supportingMigrationOnly {
                return versionsSupportingMigration
            } else {
                return versionsSupportingMigration + versionsNotSupportingMigration
            }
        }

        static var latestWithMigrationPath: ModelVersion {
            return .v3
        }

        static var latestWithoutMigrationPath: ModelVersion {
            return .v4
        }

        static func versions(after earlierVersion: ModelVersion, supportingMigrationOnly: Bool = false) -> [ModelVersion] {
            let allVersions = all(supportingMigrationOnly: supportingMigrationOnly)
            guard let earlierIndex = allVersions.index(of: earlierVersion) else {
                preconditionFailure("Unknown version (\(earlierVersion))")
            }

            return Array(allVersions.suffix(from: earlierIndex + 1))
        }
    }
}
