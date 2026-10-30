import Foundation
import AppKit

// MARK: - Engine models
//
// These mirror the payloads of the local engine's mode endpoints:
// `GET /modes`, `GET /modes/settings`, `GET /modes/app_rules`,
// `GET /capabilities`, plus the writes the Modes page needs.

struct ModeCapability: Codable, Identifiable, Equatable {
    var modeId: String
    var missing: String?
    var fix: String?
    var sizeMb: Int?
    var correction: String?

    var id: String { modeId }

    enum CodingKeys: String, CodingKey {
        case modeId = "mode_id"
        case missing
        case fix
        case sizeMb = "size_mb"
        case correction
    }
}

struct Capabilities: Codable {
    var aiLocation: String
    var correctionLocation: String
    var localTextModels: [String]
    var cloudAccess: Bool
    var modes: [ModeCapability]

    enum CodingKeys: String, CodingKey {
        case aiLocation = "ai_location"
        case correctionLocation = "correction_location"
        case localTextModels = "local_text_models"
        case cloudAccess = "cloud_access"
        case modes
    }

    func capability(forModeId id: String) -> ModeCapability? {
        modes.first { $0.modeId == id }
    }
}

struct EngineMode: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: String
    var icon: String?
    var style: String?
    var fixCorrections: Bool?
    var translateTo: String?
    var customInstructions: String?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, icon, style, tags
        case fixCorrections = "fix_corrections"
        case translateTo = "translate_to"
        case customInstructions = "custom_instructions"
    }
}

struct EngineModesDocument: Codable {
    var modes: [EngineMode]

    enum CodingKeys: String, CodingKey { case modes }
}

struct ModeAppRuleMatch: Codable, Equatable {
    var type: String
    var value: String
    var aliases: [String]?
}

struct ModeAppRule: Codable, Identifiable, Equatable {
    var id: String
    var match: ModeAppRuleMatch
    var displayName: String?
    var modeId: String
    var enabled: Bool?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case id, match, enabled, source
        case displayName = "display_name"
        case modeId = "mode_id"
    }

    var isEnabled: Bool { enabled ?? true }
}

struct ModeAppRules: Codable {
    var enabled: Bool
    var rules: [ModeAppRule]

    static let empty = ModeAppRules(enabled: true, rules: [])
}

struct ModeSettingsPayload: Codable {
    var aiLocation: String?
    var automaticAppRules: Bool?
    var activeModeId: String?

    enum CodingKeys: String, CodingKey {
        case aiLocation = "ai_location"
        case automaticAppRules = "automatic_app_rules"
        case activeModeId = "active_mode_id"
    }
}

// MARK: - Store

/// Engine-backed state for the Modes page: the modes the engine owns, per-mode
/// capabilities (what is missing), the app rules, and the "pick by app" setting.
///
/// The recording pipeline still reads the local profile, so this store is
/// read-mostly. It never publishes unless a value actually changed.
@MainActor
final class ModesStore: ObservableObject {
    @Published private(set) var engineModes: [EngineMode] = []
    @Published private(set) var capabilities: Capabilities?
    @Published private(set) var appRules: ModeAppRules = .empty
    @Published private(set) var automaticAppRules: Bool = true
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var errorMessage: String?

    private var hasMigrated = false
    private var didLoad = false

    nonisolated init() {}

    // MARK: Loading

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            async let documentData = send("GET", "modes")
            async let capabilitiesData = send("GET", "capabilities")
            async let appRulesData = send("GET", "modes/app_rules")
            async let settingsData = send("GET", "modes/settings")

            let document = try JSONDecoder().decode(EngineModesDocument.self, from: try await documentData)
            let caps = try JSONDecoder().decode(Capabilities.self, from: try await capabilitiesData)
            let rules = try JSONDecoder().decode(ModeAppRules.self, from: try await appRulesData)
            let settings = try JSONDecoder().decode(ModeSettingsPayload.self, from: try await settingsData)

            assignModes(document.modes)
            assignCapabilities(caps)
            assignAppRules(rules)
            if let auto = settings.automaticAppRules { assignAutomatic(auto) }
            didLoad = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not reach the engine."
        }
    }

    /// The engine builds its modes from the client's profiles. This sends them
    /// once so mode ids line up with the profiles. It is safe to call again:
    /// the engine reports `already_migrated` and nothing changes.
    func migrateIfNeeded(profiles: [DictyProfile]) async {
        guard !hasMigrated, !profiles.isEmpty else { return }
        hasMigrated = true
        do {
            let encoded = try JSONEncoder().encode(profiles)
            let array = try JSONSerialization.jsonObject(with: encoded)
            _ = try await send("POST", "modes/migrate", json: ["profiles": array])
            await refresh()
        } catch {
            // A migration miss only costs the capability line and app-rule
            // mapping. The page still works, so stay quiet.
        }
    }

    // MARK: Settings

    func setAutomaticAppRules(_ on: Bool) async {
        guard on != automaticAppRules else { return }
        let previous = automaticAppRules
        assignAutomatic(on)
        do {
            _ = try await send("PUT", "modes/settings", json: ["automatic_app_rules": on])
        } catch {
            assignAutomatic(previous)
        }
    }

    /// "local" or "cloud_when_better". The Models page and onboarding set this.
    func setAILocation(_ location: String) async {
        guard location != capabilities?.aiLocation else { return }
        let previous = capabilities?.aiLocation
        if var caps = capabilities {
            caps.aiLocation = location
            capabilities = caps
        }
        do {
            _ = try await send("PUT", "modes/settings", json: ["ai_location": location])
        } catch {
            if var caps = capabilities, let previous {
                caps.aiLocation = previous
                capabilities = caps
            }
            errorMessage = "Could not change where Dicty runs AI."
        }
    }

    func setActiveMode(_ modeId: String) async {
        do {
            _ = try await send("PUT", "modes/settings", json: ["active_mode_id": modeId])
        } catch {
            errorMessage = "Could not switch mode."
        }
    }

    // MARK: App rules

    func rules(forModeId modeId: String) -> [ModeAppRule] {
        appRules.rules.filter { $0.modeId == modeId }
    }

    func addAppRule(bundleId: String, name: String, modeId: String) async {
        guard !bundleId.isEmpty, !modeId.isEmpty else { return }
        var rules = appRules.rules
        if let index = rules.firstIndex(where: { $0.match.value == bundleId }) {
            rules[index].modeId = modeId
            rules[index].enabled = true
            rules[index].displayName = rules[index].displayName ?? name
        } else {
            rules.append(ModeAppRule(
                id: UUID().uuidString,
                match: ModeAppRuleMatch(type: "app", value: bundleId, aliases: nil),
                displayName: name,
                modeId: modeId,
                enabled: true,
                source: "user"
            ))
        }
        await save(rules)
    }

    func setAppRuleMode(ruleId: String, modeId: String) async {
        var rules = appRules.rules
        guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        rules[index].modeId = modeId
        await save(rules)
    }

    func setAppRuleEnabled(ruleId: String, enabled: Bool) async {
        var rules = appRules.rules
        guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        rules[index].enabled = enabled
        await save(rules)
    }

    /// Reset drops the app's assignment so it follows the automatic rules again.
    func resetAppRule(ruleId: String) async {
        let rules = appRules.rules.filter { $0.id != ruleId }
        await save(rules)
    }

    func removeAppRule(bundleId: String, modeId: String) async {
        let rules = appRules.rules.filter { !($0.match.value == bundleId && $0.modeId == modeId) }
        await save(rules)
    }

    private func save(_ rules: [ModeAppRule]) async {
        let previous = appRules
        assignAppRules(ModeAppRules(enabled: appRules.enabled, rules: rules))
        do {
            let encoded = try JSONEncoder().encode(appRules)
            let object = try JSONSerialization.jsonObject(with: encoded)
            _ = try await send("PUT", "modes/app_rules", json: ["rules": object])
        } catch {
            assignAppRules(previous)
            errorMessage = "Could not save app rules."
        }
    }

    // MARK: Capabilities

    /// Start the download a mode is waiting for. Returns the model size in MB.
    @discardableResult
    func fix(modeId: String) async -> Int? {
        do {
            let data = try await send("POST", "capabilities/fix", json: ["mode_id": modeId])
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            await refresh()
            return object?["size_mb"] as? Int
        } catch {
            errorMessage = "Could not start the download."
            return nil
        }
    }

    var loaded: Bool { didLoad }

    // MARK: Mode lookup

    /// The engine mode that owns a local profile. Matching goes from most to
    /// least precise so a migrated profile always resolves to its own mode.
    func engineMode(for profile: DictyProfile) -> EngineMode? {
        let uuid = profile.id.uuidString.lowercased()
        if let match = engineModes.first(where: { $0.id.lowercased() == uuid }) {
            return match
        }
        if let match = engineModes.first(where: { $0.name.caseInsensitiveCompare(profile.name) == .orderedSame }) {
            return match
        }
        let kind = Self.kind(for: profile)
        let style = Self.engineStyle(forLegacy: profile.dictationFormatStyle)
        if let match = engineModes.first(where: { $0.kind == kind && $0.style == style }) {
            return match
        }
        return engineModes.first(where: { $0.kind == kind })
    }

    func capability(for profile: DictyProfile) -> ModeCapability? {
        guard let mode = engineMode(for: profile), let caps = capabilities else { return nil }
        return caps.capability(forModeId: mode.id)
    }

    func modeName(forModeId id: String) -> String {
        if let mode = engineModes.first(where: { $0.id == id }) {
            return mode.name
        }
        // App rules can still point at the old client mode names until the
        // engine rewrites them. Show something friendlier than the raw id.
        switch id {
        case "dictation": return "General"
        case "meeting": return "Meeting"
        case "focused_meeting": return "Focused meeting"
        case "librarian": return "Librarian"
        case "raw": return "General"
        default: return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func kind(for profile: DictyProfile) -> String {
        DictyAudioRecorder.isSystemAudioMode(profile.activeMode) ? "meeting" : "dictation"
    }

    static func engineStyle(forLegacy legacy: String) -> String {
        switch legacy {
        case "raw", "raw_dialogue": return "exact"
        case "punctuation_fast": return "clean"
        case "book", "dialogue_structured", "dialogue_summary", "meeting_summary": return "note"
        case "email": return "email"
        case "message": return "message"
        case "code": return "code"
        default: return "clean"
        }
    }

    // MARK: Publishing (only on change)

    private func assignModes(_ value: [EngineMode]) {
        if value.map(\.id) != engineModes.map(\.id) || value != engineModes { engineModes = value }
    }

    private func assignCapabilities(_ value: Capabilities?) {
        guard let value else { return }
        if capabilities == nil || !capabilitiesEqual(capabilities, value) { capabilities = value }
    }

    private func assignAppRules(_ value: ModeAppRules) {
        if appRules.rules != value.rules || appRules.enabled != value.enabled { appRules = value }
    }

    private func assignAutomatic(_ value: Bool) {
        if automaticAppRules != value { automaticAppRules = value }
    }

    private func capabilitiesEqual(_ a: Capabilities?, _ b: Capabilities) -> Bool {
        guard let a else { return false }
        return a.aiLocation == b.aiLocation
            && a.correctionLocation == b.correctionLocation
            && a.cloudAccess == b.cloudAccess
            && a.modes == b.modes
    }

    // MARK: HTTP

    private func send(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        var headers: [String: String] = [:]
        if json != nil {
            headers["Content-Type"] = "application/json"
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        let request = EngineEndpoint.shared.request(
            normalizedPath,
            method: method,
            body: body,
            headers: headers,
            timeout: 12
        )
        let (data, response) = try await EngineEndpoint.shared.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - App identity helpers

@MainActor
enum DictyAppDirectory {
    private static var iconCache: [String: NSImage] = [:]

    /// A stable, friendly name for an app bundle id.
    static func name(for bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            if !name.isEmpty { return name }
        }
        return bundleId
    }

    static func icon(for bundleId: String) -> NSImage? {
        if let cached = iconCache[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleId] = icon
        return icon
    }
}
