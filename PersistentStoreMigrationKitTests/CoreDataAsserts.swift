//
//  CoreDataAsserts.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg Brückmann on 13.05.18.
//  Copyright © 2018 Georg C. Brückmann. All rights reserved.
//

import Foundation
import XCTest
import CoreData

/// Verifies that a persistent store can be openened given a specific managed object model.
func XCTAssertValidStore(at storeURL: URL, ofType storeType: String, for model: NSManagedObjectModel, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    do {
        try persistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: [NSReadOnlyPersistentStoreOption: true])
    } catch {
        XCTFail("Persistent store at \(storeURL) is not compatible with model (\(model)) - \(message())", file: file, line: line)
    }
}
