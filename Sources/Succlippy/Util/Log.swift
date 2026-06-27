import Foundation
import os

/// Thin logging shim so call sites stay terse.
enum Log {
    private static let logger = Logger(subsystem: "ai.succlippy.app", category: "general")

    static func info(_ message: String)  { logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    static func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
}
