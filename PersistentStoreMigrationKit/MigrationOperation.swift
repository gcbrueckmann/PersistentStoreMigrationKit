//
//  MigrationOperation.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg C. Brückmann on 26/08/15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation
import CoreData

/// A `MigrationOperation` instance encapsulates the progressive migration from one `NSManagedObjectModel` to another with an arbitrary number of intermediate models.
/// This is a companion to and implemented on top of the `MigrationPlan` class.
@objc public final class MigrationOperation: Operation {

    /// Identifies the persistent store to migrate from.
    ///
    /// This is a required operation property.
    @objc public var sourceURL: URL! {
        didSet { becomeReadyIfPossible() }
    }

    /// A string constant (such as `NSSQLiteStoreType`) that specifies the source store type.
    ///
    /// This is a required operation property.
    @objc public var sourceStoreType: String! {
        didSet { becomeReadyIfPossible() }
    }

    /// Identifies the persistent store to migrate to. May be identical to `sourceURL`.
    ///
    /// This is a required operation property.
    @objc public var destinationURL: URL! {
        didSet { becomeReadyIfPossible() }
    }

    /// A string constant (such as `NSSQLiteStoreType`) that specifies the destination store type.
    ///
    /// This is a required operation property.
    @objc public var destinationStoreType: String! {
        didSet { becomeReadyIfPossible() }
    }

    /// The model to migrate to.
    ///
    /// This is a required operation property.
    @objc public var destinationModel: NSManagedObjectModel! {
        didSet { becomeReadyIfPossible() }
    }

    /// A list of bundles to search for the source model and intermediate models.
    ///
    /// This is a required operation property.
    @objc public var bundles: [Bundle]! {
        didSet { becomeReadyIfPossible() }
    }

    /// The overall progress of the migration operation.
    @objc public let progress: Progress
    
    /// Any error that may have occured during the execution of the migration operation.
    @objc public private(set) var error: Swift.Error?

    /// Initializes a migration operation.
    ///
    /// Inserts an `NSProgress` instance into the current progress tree.
    override public required init() {
        progress = Progress(totalUnitCount: 100)
        super.init()
    }

    /// Indicates whether all required configuration properties have been set.
    private var isFullyConfigured: Bool {
        guard sourceURL != nil else { return false }
        guard sourceStoreType != nil else { return false }
        guard destinationURL != nil else { return false }
        guard destinationStoreType != nil else { return false }
        guard destinationModel != nil else { return false }
        guard bundles != nil else { return false }

        return true
    }

    /// Advances the operation’s state to `.ready`, if the operation is fully configured.
    private func becomeReadyIfPossible() {
        guard state == .awaitingConfiguration else { return }
        guard isFullyConfigured else { return }

        state = .ready
    }

    /// Defines possible migration operation states.
    @objc public enum State: Int {
        /// The migration operation is missing required configuration details.
        case awaitingConfiguration
        /// The migration operation is ready to execute.
        case ready
        /// The migration operation is executing.
        case executing
        /// The migration operation has finished executing.
        case finished
        /// The migration operation has been cancelled.
        case cancelled
    }
    /// The current state of the migration operation.
    @objc private(set) public dynamic var state: State = .awaitingConfiguration

    // MARK: NSOperation
    public override func start() {
        precondition(sourceURL != nil, "Missing source URL.")
        precondition(sourceStoreType != nil, "Missing source store type.")
        precondition(destinationURL != nil, "Missing destination URL.")
        precondition(destinationStoreType != nil, "Missing desetination store type.")
        precondition(destinationModel != nil, "Missing destination model.")
        precondition(bundles != nil, "Missing bundles.")

        state = .executing
        do {
            // Get store metadata.
            let existingStoreMetadata = try progress.performAsCurrent(withPendingUnitCount: 5) {
                return try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: sourceStoreType, at: sourceURL) as [String : AnyObject]
            }

            // Devise migration plan.
            let migrationPlan = try progress.performAsCurrent(withPendingUnitCount: 10) {
                return try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: destinationModel, bundles: bundles)
            }

            // Execute migration plan.
            try progress.performAsCurrent(withPendingUnitCount: 85) {
                try migrationPlan.executeForStore(at: sourceURL, type: sourceStoreType, destinationURL: destinationURL, storeType: destinationStoreType)
            }
        } catch {
            self.error = error
        }
        state = .finished
    }

    @objc class func keyPathsForValuesAffectingIsReady() -> Set<String> {
        return ["state"]
    }

    override public var isReady: Bool {
        return state == .ready
    }

    @objc class func keyPathsForValuesAffectingIsExecuting() -> Set<String> {
        return ["state"]
    }

    override public var isExecuting: Bool {
        return state == .executing
    }

    @objc class func keyPathsForValuesAffectingIsFinished() -> Set<String> {
        return ["state"]
    }

    override public var isFinished: Bool {
        return state == .finished
    }

    @objc class func keyPathsForValuesAffectingIsCancelled() -> Set<String> {
        return ["state"]
    }

    override public var isCancelled: Bool {
        return state == .cancelled
    }
}
