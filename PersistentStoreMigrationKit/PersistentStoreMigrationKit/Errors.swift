//
//  Errors.swift
//  PersistentStoreMigrationKit
//
//  Created by Georg C. Brückmann on 26.08.15.
//  Copyright (c) 2015 Georg C. Brückmann. All rights reserved.
//

import Foundation

public extension NSError {
	public static var persistentStoreMigrationKitDomain: String { return "com.bloo7.persistentstoremigrationkit" }
	
	public enum PersistentStoreMigrationKitCodes: Int {
		case CouldNotFindSourceModel
		case CouldNotInferMappingSteps
	}
	
	internal convenience init(persistentStoreMigrationKitCode code: PersistentStoreMigrationKitCodes, userInfo: [NSObject: AnyObject]?) {
		self.init(domain: self.dynamicType.persistentStoreMigrationKitDomain, code: code.rawValue, userInfo: userInfo)
	}
}