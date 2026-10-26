import Foundation
import AppKit

/// Client-side telemetry dispatcher that routes native macOS events to the central Dicty Engine telemetry hub.
/// Strictly OPT-IN (disabled by default). Never collects transcripts, audio, user emails, or frontmost app names.
final class TelemetryClient: @unchecked Sendable {
    static let shared = TelemetryClient()
    
    private let engineURL = EngineEndpoint.shared.baseURL.absoluteString
    private let session = EngineEndpoint.shared.session(configuration: .ephemeral)
    
    private let lock = NSLock()
    private var _isEnabled: Bool = false
    
    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            _isEnabled = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue, forKey: "dicty_share_anonymous_usage")
        }
    }
    
    private init() {
        self._isEnabled = UserDefaults.standard.bool(forKey: "dicty_share_anonymous_usage")
    }
    
    /// Synchronizes telemetry opt-in preference with the local engine on startup.
    func syncWithEngine() {
        guard let url = URL(string: "\(engineURL)/telemetry/settings") else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let enabled = json["share_anonymous_usage"] as? Bool else { return }
            self.isEnabled = enabled
        }.resume()
    }
    
    /// Tracks a native client event only if anonymous telemetry is explicitly enabled.
    func track(_ event: String, properties: [String: Any]? = nil) {
        guard isEnabled else { return }
        
        let props = properties ?? [:]
        
        #if DEBUG
        if ProcessInfo.processInfo.environment["DICTY_DEBUG"] == "1" {
            let propsStr = props.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            print("[TelemetryClient] \(event) | \(propsStr)")
        }
        #endif
        
        guard let url = URL(string: "\(engineURL)/telemetry/event") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0
        
        let payload: [String: Any] = [
            "event": event,
            "properties": props
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        request.httpBody = httpBody
        
        session.dataTask(with: request) { _, _, _ in
            // Fire-and-forget; zero impact on client UI thread
        }.resume()
    }
    
    /// Backward-compatible overload ignoring userId to protect user privacy.
    func track(_ event: String, properties: [String: Any]? = nil, userId: String?) {
        track(event, properties: properties)
    }
    
    /// Deprecated / No-op: Dicty enforces zero-knowledge telemetry and never links personal emails or user accounts.
    func identify(userId: String) {
        // No-op for privacy
    }
}
