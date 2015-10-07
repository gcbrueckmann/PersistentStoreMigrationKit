# PersistentStoreMigrationKit

PersistentStoreMigrationKit lets perform progressive migrations of Core
Data persistent stores easily. It is written in Swift 2.

## How It Works

Persistent stores are migrated progressively according to a migration
plan. To devise a migration plan, PersistentStoreMigrationKit requires
the metadata from the existing store, the destination managed object
model that you'll eventually use to initialize a persistent store
coordinator and an array of bundles in which to look for intermediate
models. When you have a migration, you are then ready to execute it. If
the execution succeeds, the persistent store will be migrated to the
latest model you specified.

### Migration Plans

```swift
func configureManagedObjectContextForURL(persistentStoreURL: NSURL) throws -> NSManagedObjectContext {
    // These are the required prequisites.
    let latestModel: NSManagedObjectModel
    let modelBundles: [NSBundle.mainBundle()]
    let persistentStoreType = NSSQLiteStoreType
    
    // Load metadata from persistent store.
    let persistentStoreMetadata: [String: AnyObject]?
    do {
    	persistentStoreMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(persistentStoreType, URL: persistentStoreURL)
    } catch NSCocoaError.FileReadNoSuchFileError {
        // The persistent store doesn't exist,
        // so no migration is necessary.
    	persistentStoreMetadata = nil
    } catch {
    	print("Could not retrieve metadata for persistent store at \(persistentStoreURL): \(error)")
    	throw error
    }
    
    // Devise and execute migration plan, if metadata is available,
    // i.e. the persistent store already exists.
	if let persistentStoreMetadata = persistentStoreMetadata {
		let migrationPlan: MigrationPlan
		do {
			migrationPlan = try MigrationPlan(storeMetadata: persistentStoreMetadata, destinationModel: latestModel, bundles: modelBundles)
		} catch {
			print("Could not devise migration plan for persistent store at \(persistentStoreURL): \(error)")
			throw error
		}
		do {
			try migrationPlan.executeForStoreAtURL(persistentStoreURL, type: persistentStoreType, destinationURL: persistentStoreURL, storeType: persistentStoreType)
		} catch {
			print("Could not execute migration plan for persistent store at \(persistentStoreURL): \(error)")
			throw error
		}
	}
    
    // Configure persistent store coordinator and managed object context.
	let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
	do {
		try persistentStoreCoordinator.addPersistentStoreWithType(persistentStoreType, configuration: nil, URL: persistentStoreURL, options: nil)
	} catch {
		print("Could not load persistent store at \(persistentStoreURL): \(error).")
        throw error
	}
	return NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
}
```

### Migration Operations

PersistentStoreMigrationKit also comes with the `MigrationOperation`
class that conveniently wraps the migration plan workflow into an
`NSOperation` subclass:

```swift
func configureManagedObjectContextForURL(persistentStoreURL: NSURL, completionHandler: (NSManagedObjectContext?, error: ErrorType?) -> Void) {
    // These are the required prequisites.
    let latestModel: NSManagedObjectModel
    let modelBundles: [NSBundle.mainBundle()]
    let persistentStoreType = NSSQLiteStoreType
    
	let migrationOperation = MigrationOperation()
	migrationOperation.sourceURL = persistentStoreURL
	migrationOperation.sourceStoreType = persistentStoreType
	migrationOperation.destinationURL = persistentStoreURL
	migrationOperation.destinationStoreType = persistentStoreType
	migrationOperation.destinationModel = latestModel
	migrationOperation.bundles = modelBundles
	migrationOperation.completionBlock = {
        do {
            if let error = migrationOperation.error { throw error }
            // Configure persistent store coordinator and managed object context.
        	let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: latestModel)
        	do {
        		try persistentStoreCoordinator.addPersistentStoreWithType(persistentStoreType, configuration: nil, URL: persistentStoreURL, options: nil)
        	} catch {
        		print("Could not load persistent store at \(persistentStoreURL): \(error).")
                throw error
        	}
        	completionHandler(NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType), error: nil)
        } catch {
            completionHandler(nil, error: error)
        }
	}
	operationQueue.addOperation(migrationOperation)
}
```

### Progress Reporting

Both the `MigrationPlan` and `MigrationOperation` classes maintain an
`NSProgress` instance. You can insert it into your own progress tree
when initializing the plan or operation:

```swift
let migrationProgress = NSProgress(totalUnitCount: 1)
let migrationPlan: MigrationPlan
do {
	migrationProgress.becomeCurrentWithPendingUnitCount(1)
	defer { migrationProgress.resignCurrent() }
	migrationPlan = try MigrationPlan(storeMetadata: persistentStoreMetadata, destinationModel: latestModel, bundles: modelBundles)
} catch {
    // Handle error.
}
```

## Credits

[Georg C. Brückmann](http://gcbrueckmann.de)

This project was inspired by and profitted heavily from the article
[Custom Core Data
Migrations](https://www.objc.io/issues/4-core-data/core-data-migration/)
 by [Martin Hwasser](https://github.com/hwaxxer) and, of course, pretty
much everything [Marcus S. Zarra](https://twitter.com/mzarra) has ever
said/written about Core Data. Seriously, do yourself a favor and [buy
his book](https://pragprog.com/book/mzcd2/core-data).

## License

PersistentStoreMigrationKit is released under the MIT License. See the
bundled [LICENSE](LICENSE) file for details.
