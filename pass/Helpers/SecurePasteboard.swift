//
//  SecurePasteboard.swift
//  pass
//
//  Created by Yishi Lin on 2017/7/27.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import passKit

class SecurePasteboard {
    static let shared = SecurePasteboard()

    func copy(textToCopy: String?, expirationTime: Double = Globals.pasteboardExpirationTime) {
        Utils.copyToPasteboard(textToCopy: textToCopy ?? "", expirationTime: expirationTime)
    }
}
