import Foundation
import os.log

final class MediaLogger: Sendable {
    static let shared = MediaLogger()
    
    // Create a dedicated unified logger for MediaPlayback
    private let osLogger = Logger(subsystem: "com.kazmin.dicty", category: "MediaPlayback")
    
    private init() {
    }
    
    func log(_ message: String) {
        // Send message to the unified OS logging system.
        // It handles timestamps, threading, rotation, and compression automatically.
        osLogger.notice("\(message, privacy: .public)")
        
        // Keep console print for active Xcode debugging
        print("[MediaLogger] \(message)")
    }
}
