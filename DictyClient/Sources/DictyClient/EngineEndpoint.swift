import AVFoundation
import Foundation
import Security

extension Notification.Name {
    static let dictyEngineAuthFailed = Notification.Name("dicty.engine.authFailed")
    static let dictyEngineAuthRecovered = Notification.Name("dicty.engine.authRecovered")
}

/// The single source of truth for the local engine's address and session token.
///
/// Every HTTP/WebSocket call to the local engine must go through this type. It owns:
/// - the loopback host and port,
/// - the `X-Dicty-Token` header,
/// - reading the token written by `engine_auth.py`,
/// - the one-shot 401 retry after the token file is rewritten by a restarted engine.
final class EngineEndpoint: @unchecked Sendable {
    static let shared = EngineEndpoint()

    static let host = "127.0.0.1"
    static let port = 8075
    private static let avHeaderFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    let baseURL = URL(string: "http://127.0.0.1:8075")!
    let webSocketBaseURL = URL(string: "ws://127.0.0.1:8075")!

    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedLaunchToken: String?
    private var authFailed = false

    let session: URLSession
    let webSocketSession: URLSession
    let bareSession: URLSession

    private init() {
        bareSession = URLSession(configuration: .ephemeral)
        // WebSocket tasks do not support custom URLProtocols. The token is put
        // directly on the upgrade request by webSocketRequest(_:).
        webSocketSession = URLSession(configuration: .default)

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [EngineAuthURLProtocol.self] + (configuration.protocolClasses ?? [])
        session = URLSession(configuration: configuration)
    }

    // MARK: - URLs

    func isEngineURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        guard url.host == Self.host || url.host == "localhost" else { return false }
        return url.port == Self.port
    }

    func url(_ path: String, query: [String: String]? = nil) -> URL {
        makeURL(base: baseURL, path: path, query: query)
    }

    func webSocketURL(_ path: String, query: [String: String]? = nil) -> URL {
        makeURL(base: webSocketBaseURL, path: path, query: query)
    }

    private func makeURL(base: URL, path: String, query: [String: String]?) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = query?
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    // MARK: - Requests

    func request(
        _ path: String,
        method: String = "GET",
        query: [String: String]? = nil,
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        if let timeout {
            request.timeoutInterval = timeout
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        authorize(&request)
        return request
    }

    func webSocketRequest(_ path: String, query: [String: String]? = nil) -> URLRequest {
        var request = URLRequest(url: webSocketURL(path, query: query))
        authorize(&request)
        return request
    }

    /// AVFoundation bypasses URLSession, so it needs the auth header through asset options.
    func audioAsset(for url: URL) -> AVURLAsset {
        guard isEngineURL(url), let token = currentToken() else {
            return AVURLAsset(url: url)
        }
        return AVURLAsset(
            url: url,
            options: [Self.avHeaderFieldsKey: ["X-Dicty-Token": token]]
        )
    }

    /// Adds the current session token to a request targeting the local engine.
    /// Cloud requests are left untouched.
    func authorize(_ request: inout URLRequest) {
        guard isEngineURL(request.url) else { return }
        guard let token = currentToken() else { return }
        request.setValue(token, forHTTPHeaderField: "X-Dicty-Token")
    }

    /// Returns a session that also injects the engine token. Use this for engine calls
    /// that need a custom timeout instead of `session`.
    func session(configuration: URLSessionConfiguration) -> URLSession {
        let configuration = configuration.copy() as! URLSessionConfiguration
        var protocols = configuration.protocolClasses ?? []
        let identity = ObjectIdentifier(EngineAuthURLProtocol.self)
        if !protocols.contains(where: { ObjectIdentifier($0) == identity }) {
            protocols.insert(EngineAuthURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = protocols
        return URLSession(configuration: configuration)
    }

    // MARK: - Token lifecycle

    /// Token used when this app launches the engine. It is passed through
    /// `DICTY_SESSION_TOKEN` and the engine writes the same value to engine.token.
    var launchToken: String {
        lock.lock()
        defer { lock.unlock() }

        if let cachedLaunchToken {
            return cachedLaunchToken
        }

        let environmentToken = ProcessInfo.processInfo.environment["DICTY_SESSION_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (environmentToken?.isEmpty == false) ? environmentToken! : Self.generateToken()
        cachedLaunchToken = token
        if cachedToken == nil {
            cachedToken = token
        }
        return token
    }

    /// Environment variables that must be injected into the engine process.
    var launchEnvironment: [String: String] {
        [
            "DICTY_SESSION_TOKEN": launchToken,
        ]
    }

    /// Used when the engine was already running before this client launched.
    /// Reads the token file without changing the token used for a new launch.
    func adoptRunningEngineToken() {
        guard let token = Self.readTokenFile() else { return }
        lock.lock()
        cachedToken = token
        lock.unlock()
    }

    func currentToken() -> String? {
        lock.lock()
        if let cachedToken {
            lock.unlock()
            return cachedToken
        }
        lock.unlock()

        guard let diskToken = Self.readTokenFile() else { return nil }

        lock.lock()
        if cachedToken == nil {
            cachedToken = diskToken
        }
        let token = cachedToken
        lock.unlock()
        return token
    }

    @discardableResult
    func reloadTokenFromDisk() -> String? {
        guard let diskToken = Self.readTokenFile() else { return nil }
        lock.lock()
        cachedToken = diskToken
        lock.unlock()
        return diskToken
    }

    /// The engine auth middleware returns exactly {"error": "unauthorized"}.
    /// Other 401s (for example invalid login credentials) must not look like a lost engine.
    func isTokenRejection(data: Data?) -> Bool {
        guard let data,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (payload["error"] as? String) == "unauthorized"
    }

    func noteAuthFailure() {
        lock.lock()
        let shouldNotify = !authFailed
        authFailed = true
        lock.unlock()

        guard shouldNotify else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .dictyEngineAuthFailed, object: nil)
        }
    }

    func noteAuthSuccess() {
        lock.lock()
        let shouldNotify = authFailed
        authFailed = false
        lock.unlock()

        guard shouldNotify else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .dictyEngineAuthRecovered, object: nil)
        }
    }

    var isAuthFailed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return authFailed
    }

    // MARK: - Token file

    static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["DICTY_DATA_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dicty", isDirectory: true)
    }

    static var tokenFileURL: URL {
        dataDirectory.appendingPathComponent("engine.token")
    }

    private static func readTokenFile() -> String? {
        guard let data = try? Data(contentsOf: tokenFileURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = payload["token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        if status != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Adds the engine token to every loopback engine request and retries once with a
/// freshly-read token when the engine returns 401 (for example after an update restart).
final class EngineAuthURLProtocol: URLProtocol, @unchecked Sendable {
    private var dataTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        EngineEndpoint.shared.isEngineURL(request.url)
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        EngineEndpoint.shared.isEngineURL(task.originalRequest?.url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        var request = request
        EngineEndpoint.shared.authorize(&request)
        return request
    }

    override func startLoading() {
        perform(request: request, allowRetry: true)
    }

    private func perform(request originalRequest: URLRequest, allowRetry: Bool) {
        var authorizedRequest = originalRequest
        EngineEndpoint.shared.authorize(&authorizedRequest)
        let request = authorizedRequest

        let task = EngineEndpoint.shared.bareSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            let tokenRejected: Bool
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                tokenRejected = EngineEndpoint.shared.isTokenRejection(data: data)
            } else {
                tokenRejected = false
            }

            if tokenRejected,
               allowRetry,
               let _ = EngineEndpoint.shared.reloadTokenFromDisk() {
                self.perform(request: originalRequest, allowRetry: false)
                return
            }

            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let response {
                if tokenRejected {
                    EngineEndpoint.shared.noteAuthFailure()
                } else if request.url?.path != "/health" {
                    // /health is exempt from auth, so a 200 there says nothing about the token.
                    EngineEndpoint.shared.noteAuthSuccess()
                }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }

            self.client?.urlProtocolDidFinishLoading(self)
        }

        self.dataTask = task
        task.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }
}
