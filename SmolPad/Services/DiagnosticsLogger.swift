import Foundation
import OSLog

enum DiagnosticsLogger {
    static let app = Logger(subsystem: "com.smol.smolpad", category: "app")
    static let ai = Logger(subsystem: "com.smol.smolpad", category: "ai")
    static let context = Logger(subsystem: "com.smol.smolpad", category: "context")
    static let voice = Logger(subsystem: "com.smol.smolpad", category: "voice")
    static let network = Logger(subsystem: "com.smol.smolpad", category: "network")

    static func truncated(_ value: String, limit: Int = 600) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]) + "…"
    }

    static func jsonPreview(from object: Any, limit: Int = 2000) -> String {
        let sanitized = redact(object)

        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "<unserializable payload>"
        }

        return truncated(string, limit: limit)
    }

    static func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var redacted: [String: Any] = [:]
            for (key, rawValue) in dictionary {
                let lower = key.lowercased()
                if lower.contains("authorization") || lower.contains("api_key") || lower == "apikey" {
                    redacted[key] = "<redacted>"
                    continue
                }
                if lower == "data" {
                    redacted[key] = "<base64-image-redacted>"
                    continue
                }
                if lower == "url", let string = rawValue as? String, string.hasPrefix("data:image") {
                    redacted[key] = "<data-image-url-redacted>"
                    continue
                }
                redacted[key] = redact(rawValue)
            }
            return redacted
        }

        if let array = value as? [Any] {
            return array.map { redact($0) }
        }

        if let string = value as? String {
            return truncated(string, limit: 1200)
        }

        return value
    }
}
