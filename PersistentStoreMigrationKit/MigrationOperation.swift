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
public final class MigrationOperation: NSOperation {
	/// Identifies the persistent store to migrate from.
	public var sourceURL: NSURL!
	/// A string constant (such as `NSSQLiteStoreType`) that specifies the source store type.
	public var sourceStoreType: String!
	/// Identifies the persistent store to migrate to. May be identical to `sourceURL`.
	public var destinationURL: NSURL!
	/// A string constant (such as `NSSQLiteStoreType`) that specifies the destination store type.
	public var destinationStoreType: String!
	/// The model to migrate to.
	public var destinationModel: NSManagedObjectModel!
	/// A list of bundles to search for the source model and intermediate models.
	public var bundles: [NSBundle]!
	/// The overall progress of the migration operation.
	public let progress: NSProgress
	/// Any error that may have occured during the execution of the migration operation.
	public private(set) var error: ErrorType?
	
	/// Initializes a migration operation.
	/// 
	/// Inserts an `NSProgress` instance into the current progress tree.
	override public required init() {
		progress = NSProgress(totalUnitCount: 100)
		super.init()
	}
	
	/// Defines possible migration operation states.
	@objc public enum State: Int {
		/// The migration operation is ready to execute.
		case Ready
		/// The migration operation is executing.
		case Executing
		case Failed
		/// The migration operation has finished executing.
		case Finished
		/// The migration operation has been cancelled.
		case Cancelled
	}
	/// The current state of the migration operation.
	private(set) public dynamic var state = State.Ready
	
	private func cancelWithError(error: NSError) {
		self.error = error
		state = .Cancelled
	}
	
	// MARK: NSOperation
	public override func start() {
		precondition(sourceURL != nil, "Missing source URL.")
		precondition(sourceStoreType != nil, "Missing source store type.")
		precondition(destinationURL != nil, "Missing destination URL.")
		precondition(destinationStoreType != nil, "Missing desetination store type.")
		precondition(destinationModel != nil, "Missing destination model.")
		precondition(bundles != nil, "Missing bundles.")
		state = .Executing
		
		let existingStoreMetadata: [String: AnyObject]
		do {
			existingStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(sourceStoreType, URL: sourceURL)
		} catch let metadataError as NSError {
			cancelWithError(metadataError)
			return
		}
		
		// Devise migration plan.
		let migrationPlan: MigrationPlan
		do {
			migrationPlan = try MigrationPlan(storeMetadata: existingStoreMetadata, destinationModel: destinationModel, bundles: bundles)
		} catch let migrationPlanError as NSError {
			cancelWithError(migrationPlanError)
			return
		}
		progress.completedUnitCount += 10
		
		// Execute migration plan.
		progress.becomeCurrentWithPendingUnitCount(90)
		do {
			try migrationPlan.executeForStoreAtURL(sourceURL, type: sourceStoreType, destinationURL: destinationURL, storeType: destinationStoreType)
		} catch let migrationPlanExecutionError as NSError {
			cancelWithError(migrationPlanExecutionError)
			return
		}
		progress.resignCurrent()
		
		state = .Finished
	}
	
	class func keyPathsForValuesAffectingIsReady() -> Set<String> {
		return ["state"]
	}
	
	override public var ready: Bool {
		return state == .Ready
	}
	
	class func keyPathsForValuesAffectingIsExecuting() -> Set<String> {
		return ["state"]
	}
	
	override public var executing: Bool {
		return state == .Executing
	}
	
	class func keyPathsForValuesAffectingIsFinished() -> Set<String> {
		return ["state"]
	}
	
	override public var finished: Bool {
		return state == .Finished
	}
	
	class func keyPathsForValuesAffectingIsCancelled() -> Set<String> {
		return ["state"]
	}
	
	override public var cancelled: Bool {
		return state == .Cancelled
	}
}
