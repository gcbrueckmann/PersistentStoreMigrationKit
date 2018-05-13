//
//  Bundle+Test.swift
//  PersistentStoreMigrationKitTests
//
//  Created by Georg Brückmann on 13.05.18.
//  Copyright © 2018 Georg C. Brückmann. All rights reserved.
//

import Foundation

extension Bundle {

    static let test = Bundle(for: TokenClassInTestBundle.self)

    private class TokenClassInTestBundle {
        // Used solely to have something to pass to Bundle.init(for:)
    }
}
