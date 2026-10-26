import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Models
struct DictyModel: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var size: String
    var speed: Double
    var accuracy: Double
    var is_downloaded: Bool?
    var is_cloud: Bool?
    var category: String? // "voice" or "text"
    var description: String?
    var supports_translation: Bool? = false
    var quantization: String?
    var provider: String?
    
    var isTextModel: Bool {
        if category == "text" { return true }
        let lowId = id.lowercased()
        if category != "voice" && (lowId.contains("claude") || lowId.contains("gpt-5") || lowId.contains("gpt-4") || lowId.contains("gemini") || lowId.contains("deepseek") || lowId.contains("grok") || lowId.contains("nemotron") || lowId.contains("qwen") || lowId.contains("kimi") || lowId.contains("glm") || lowId.contains("minimax") || lowId.contains("llama-3")) {
            return true
        }
        return false
    }
    
    var sizeInMB: Double {
        let sizeStr = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if sizeStr.lowercased().contains("cloud") { return 0 }
        let parts = sizeStr.components(separatedBy: " ")
        guard let num = Double(parts.first ?? "") else { return 0 }
        let unit = (parts.count > 1 ? parts[1] : "").uppercased()
        if unit == "GB" { return num * 1024.0 }
        else if unit == "MB" { return num }
        else if unit == "KB" { return num / 1024.0 }
        return num
    }
}

struct LocalLLMModelItem: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var display_name: String?
    var tag: String
    var description: String
    var size_bytes: Int64
    var approx_ram: String?
    var downloaded: Bool
    var is_active: Bool
}

struct LocalLLMAddonStatus: Codable, Equatable {
    var installed: Bool
    var running: Bool
    var stage: String
    var progress: Double
    var downloaded_bytes: Int64
    var total_bytes: Int64
    var error: String?
    var disk_usage_bytes: Int64
    var model_id: String?
    var model_name: String?
    var active_model_id: String?
    var target_model_id: String?
    var target_model_name: String?
    var available_models: [LocalLLMModelItem]?
}

struct ModelsResponse: Codable {
    var models: [DictyModel]
}

struct OpenRouterModelInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String?
    var context_length: Int?
    var prompt_price_per_m: Double?
    var completion_price_per_m: Double?
}

enum OpenRouterSortOption: String, CaseIterable, Identifiable {
    case mostPopular = "most-popular"
    case throughputHighToLow = "throughput-high-to-low"
    case throughputLowToHigh = "throughput-low-to-high"
    case latencyLowToHigh = "latency-low-to-high"
    case priceLowToHigh = "pricing-low-to-high"
    case priceHighToLow = "pricing-high-to-low"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .mostPopular: return "Most Popular"
        case .throughputHighToLow: return "Throughput: High to Low"
        case .throughputLowToHigh: return "Throughput: Low to High"
        case .latencyLowToHigh: return "Latency: Low to High"
        case .priceLowToHigh: return "Price: Low to High"
        case .priceHighToLow: return "Price: High to Low"
        }
    }
}

extension OpenRouterModelInfo {
    var isFree: Bool {
        let lid = id.lowercased()
        return lid.contains(":free") || ((prompt_price_per_m ?? 1.0) == 0.0 && (completion_price_per_m ?? 1.0) == 0.0)
    }
    
    var isFast: Bool {
        let lid = id.lowercased()
        return lid.contains("flash") || lid.contains("mini") || lid.contains("haiku") || lid.contains("turbo") || lid.contains("nano") || lid.contains("fast") || lid.contains("lite") || lid.contains("lightning")
    }
    
    var isReasoning: Bool {
        let lid = id.lowercased()
        let lname = name.lowercased()
        return lid.contains(":thinking") || lid.contains("deepseek-r1") || lid.contains("/o1") || lid.contains("/o3") || lid.contains("qwq") || lname.contains("thinking") || lname.contains("reasoner") || lname.contains("reasoning")
    }
    
    var cleanDisplayName: String {
        if let colonIdx = name.firstIndex(of: ":") {
            let after = name[name.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { return after }
        }
        return name
    }
    
    var providerName: String {
        let lid = id.lowercased()
        if lid.contains("anthropic/") || lid.contains("claude") { return "Claude" }
        if lid.contains("openai/") { return "OpenAI" }
        if lid.contains("google/") { return "Google" }
        if lid.contains("deepseek/") { return "DeepSeek" }
        if lid.contains("x-ai/") { return "xAI" }
        if lid.contains("nvidia/") { return "NVIDIA" }
        if lid.contains("qwen/") || lid.contains("alibaba/") { return "Qwen" }
        if lid.contains("moonshot") { return "Moonshot" }
        if lid.contains("z-ai/") || lid.contains("zhipu/") || lid.contains("thudm/") { return "Zhipu" }
        if lid.contains("minimax/") { return "MiniMax" }
        if lid.contains("meta-llama/") || lid.contains("meta/") { return "Meta" }
        if lid.contains("mistralai/") { return "Mistral" }
        return id.components(separatedBy: "/").first?.capitalized ?? "Cloud"
    }
    
    var priceText: String {
        if isFree { return "Free" }
        if let prompt = prompt_price_per_m, let comp = completion_price_per_m, (prompt > 0 || comp > 0) {
            return String(format: "$%.2f in · $%.2f out per 1M tokens", prompt, comp)
        }
        return ""
    }
}

struct OpenRouterModelsResponse: Codable {
    var models: [OpenRouterModelInfo]
}

struct ActiveModelResponse: Codable {
    var active_model: String
    var active_text_model: String?
}

struct DictyHistory: Codable, Identifiable {
    var id: String
    var timestamp: String
    var text: String
    var mode: String
    var audio_file: String
    var speaking_wpm: Int?
    var engine_wpm: Int?
    var credits_used: Int?
    var summary: String?
    var reprocessed_at: String?
    var title: String?
    var tags: [String]?
    var has_audio: Bool?
    var voice: String?
    var duration: Double?
    var notes: String?
    var app_id: String?
    var app_name: String?
    var mode_id: String?
    var mode_reason: String?
    
    var isAudioAvailable: Bool {
        if let hasAudio = has_audio {
            return hasAudio && !audio_file.isEmpty
        }
        return !audio_file.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, text, mode, audio_file
        case speaking_wpm, engine_wpm, credits_used, summary, reprocessed_at, title, tags, has_audio, voice, duration, notes
        case app_id, app_name, mode_id, mode_reason
    }

    init(id: String, timestamp: String, text: String, mode: String, audio_file: String = "", speaking_wpm: Int? = nil, engine_wpm: Int? = nil, credits_used: Int? = nil, summary: String? = nil, reprocessed_at: String? = nil, title: String? = nil, tags: [String]? = nil, has_audio: Bool? = nil, voice: String? = nil, duration: Double? = nil, notes: String? = nil, app_id: String? = nil, app_name: String? = nil, mode_id: String? = nil, mode_reason: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.mode = mode
        self.audio_file = audio_file
        self.speaking_wpm = speaking_wpm
        self.engine_wpm = engine_wpm
        self.credits_used = credits_used
        self.summary = summary
        self.reprocessed_at = reprocessed_at
        self.title = title
        self.tags = tags
        self.has_audio = has_audio
        self.voice = voice
        self.duration = duration
        self.notes = notes
        self.app_id = app_id
        self.app_name = app_name
        self.mode_id = mode_id
        self.mode_reason = mode_reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "dictation"
        self.audio_file = try container.decodeIfPresent(String.self, forKey: .audio_file) ?? ""
        self.speaking_wpm = try container.decodeIfPresent(Int.self, forKey: .speaking_wpm)
        self.engine_wpm = try container.decodeIfPresent(Int.self, forKey: .engine_wpm)
        self.credits_used = try container.decodeIfPresent(Int.self, forKey: .credits_used)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.reprocessed_at = try container.decodeIfPresent(String.self, forKey: .reprocessed_at)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.has_audio = try container.decodeIfPresent(Bool.self, forKey: .has_audio)
        self.voice = try container.decodeIfPresent(String.self, forKey: .voice)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.app_id = try container.decodeIfPresent(String.self, forKey: .app_id)
        self.app_name = try container.decodeIfPresent(String.self, forKey: .app_name)
        self.mode_id = try container.decodeIfPresent(String.self, forKey: .mode_id)
        self.mode_reason = try container.decodeIfPresent(String.self, forKey: .mode_reason)
    }
}

// MARK: - App Rules Models

struct AppRuleMatch: Codable, Equatable, Hashable {
    var type: String // "bundle_id", "process_name", or "domain"
    var value: String
}

struct AppRule: Codable, Identifiable, Equatable {
    var id: String
    var match: AppRuleMatch
    var mode_id: String
    var display_name: String?
    var enabled: Bool
    var is_default: Bool
    var source: String?
    var overridden: Bool?
    var created_at: Double?
    var updated_at: Double?

    enum CodingKeys: String, CodingKey {
        case id, match, mode_id, display_name, enabled, is_default, source, overridden, created_at, updated_at
    }

    init(id: String, match: AppRuleMatch, mode_id: String, display_name: String? = nil, enabled: Bool = true, is_default: Bool = false, source: String? = nil, overridden: Bool? = nil, created_at: Double? = nil, updated_at: Double? = nil) {
        self.id = id
        self.match = match
        self.mode_id = mode_id
        self.display_name = display_name
        self.enabled = enabled
        self.is_default = is_default
        self.source = source
        self.overridden = overridden
        self.created_at = created_at
        self.updated_at = updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        match = try container.decode(AppRuleMatch.self, forKey: .match)
        mode_id = try container.decode(String.self, forKey: .mode_id)
        display_name = try container.decodeIfPresent(String.self, forKey: .display_name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        source = try container.decodeIfPresent(String.self, forKey: .source)
        if let d = try container.decodeIfPresent(Bool.self, forKey: .is_default) {
            is_default = d
        } else {
            is_default = source == "builtin" || source == "builtin_override" || id.hasPrefix("builtin.")
        }
        if let o = try container.decodeIfPresent(Bool.self, forKey: .overridden) {
            overridden = o
        } else {
            overridden = source == "builtin_override"
        }
        created_at = try container.decodeIfPresent(Double.self, forKey: .created_at)
        updated_at = try container.decodeIfPresent(Double.self, forKey: .updated_at)
    }
}

struct AppRulesSettings: Codable, Equatable {
    var enabled: Bool = true
    var override_scope: String = "recording" // "recording" or "manual"
}

struct AppRulesResponse: Codable {
    var settings: AppRulesSettings
    var rules: [AppRule]
}

struct AppRuleResolveResponse: Codable {
    var resolved_mode: String
    var reason: String
    var rule_id: String?
    var app_id: String?
    var domain: String?
}

public struct AppRuleSuggestion: Codable, Equatable {
    public var app_id: String
    public var app_name: String
    public var mode_id: String
    public var count: Int?

    public init(app_id: String, app_name: String, mode_id: String, count: Int? = nil) {
        self.app_id = app_id
        self.app_name = app_name
        self.mode_id = mode_id
        self.count = count
    }
}

struct AppRuleModeOption: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

let availableAppRuleModes: [AppRuleModeOption] = [
    AppRuleModeOption(id: "dictation", name: "General Dictation", icon: "mic.fill"),
    AppRuleModeOption(id: "message", name: "Message", icon: "message.fill"),
    AppRuleModeOption(id: "email", name: "Email", icon: "envelope.fill"),
    AppRuleModeOption(id: "code", name: "Code", icon: "curlybraces"),
    AppRuleModeOption(id: "note", name: "Note", icon: "note.text"),
    AppRuleModeOption(id: "book", name: "Book / Prose", icon: "book.fill"),
    AppRuleModeOption(id: "issue", name: "Issue", icon: "exclamationmark.circle.fill"),
    AppRuleModeOption(id: "librarian", name: "Librarian", icon: "terminal.fill")
]

struct RetentionSettings: Codable {
    var retention_period: String
    var scrub_audio_immediately: Bool
}

struct HistoryUpdateResponse: Codable {
    var status: String
    var record: DictyHistory?
    var message: String?
}

struct HistoryResponse: Codable {
    var history: [DictyHistory]
}

struct ReprocessResponse: Codable {
    var status: String
    var record: DictyHistory?
    var message: String?
}

struct DictyDevice: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var is_default: Bool
}

struct DeviceResponse: Codable {
    var devices: [DictyDevice]
}

struct DictyPromptInfo: Codable, Identifiable {
    var id: String { key }
    var key: String
    var description: String
    var default_value: String
    var active_value: String
    var is_custom: Bool
}

struct VoiceThought: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var timestamp: Double
    var text: String
    var source: String?
    var git_branch: String?
    var git_commit: String?
    var tags: [String]?
    var updated_at: Double?
}

struct VoiceQueueResponse: Codable {
    var status: String
    var items: [VoiceThought]
    var count: Int
}


struct AuthStatusResponse: Codable {
    let logged_in: Bool
    let email: String?
    let is_pro: Bool
    let offline_mode: Bool
}
