//
//  NSManagedObjectModel+Aggregation.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg Brückmann on 12.05.18.
//  Copyright © 2018 Georg C. Brückmann. All rights reserved.
//

import Foundation

extension NSManagedObjectModel {

    /// Aggregates all valid models in the given bundles.
    ///
    /// - Attention: Invalid model files will trigger assertion failures.
    static func models(in bundles: [Bundle]) -> [NSManagedObjectModel] {
        var modelURLs: [URL] = []
        // Collect simple Core Data model URLs
        modelURLs += bundles.flatMap { (bundle) in
            return bundle.urls(forResourcesWithExtension: "mom", subdirectory: nil) ?? []
        }
        // Collect versioned Core Data model URLs
        modelURLs += bundles.flatMap { (bundle) -> [URL] in
            guard let modelBundleURLs = bundle.urls(forResourcesWithExtension: "momd", subdirectory: nil) else { return [] }
            return modelBundleURLs.flatMap { (modelBundleURL) -> [URL] in
                guard let modelBundle = Bundle(url: modelBundleURL) else {
                    assertionFailure("\(modelBundleURL) is not a valid versioned Core Data model (bundle).")
                    return []
                }
                return modelBundle.urls(forResourcesWithExtension: "mom", subdirectory: nil) ?? []
            }
        }
        // Load models at all the above URLs
        return modelURLs.compactMap { (modelURL) in
            guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
                assertionFailure("\(modelURL) is not a valid Core Data model.")
                return nil
            }
            return model
        }
    }
}
