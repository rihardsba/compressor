//
//  RecordingConfig.swift
//  Compressor
//
//  Created by Rihards Baumanis on 15/07/2019.
//  Copyright © 2019 Rich. All rights reserved.
//

import UIKit

struct RecordingConfig {
    private static let compressedFileName = "compressed.mov"

    private static var documentsDirectoryURL: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var compressedRecordingURL: URL {
        return documentsDirectoryURL.appendingPathComponent(RecordingConfig.compressedFileName)
    }

    static func clearCompressed() {
        let manager = FileManager.default

        if manager.fileExists(atPath: compressedRecordingURL.path) {
            try? manager.removeItem(at: compressedRecordingURL)
        }
        
    }
}
