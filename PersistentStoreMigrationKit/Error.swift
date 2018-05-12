//
//  Error.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg Brückmann on 12.05.18.
//  Copyright © 2018 Georg C. Brückmann. All rights reserved.
//

import Foundation

public enum Error: Swift.Error {
    /// Model version hashes are missing from store metadata.
    case missingStoreModelVersionHashes
    /// Could not find the source model for a migration step.
    case couldNotFindSourceModel
    /// Could not find a destination and mapping model for a migration step.
    case couldNotInferMappingSteps
}
