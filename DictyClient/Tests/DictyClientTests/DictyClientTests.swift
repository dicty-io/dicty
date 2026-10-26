import Foundation
import SwiftUI
import AppKit
#if canImport(XCTest)
import XCTest
#endif
@testable import Dicty

#if canImport(XCTest)
@MainActor
final class DictyClientTests: XCTestCase {
    
    // MARK: - 1. Model Decoding & Properties
    
    func testDictyModelDecodingAndSizeCalculation() throws {
        let json = """
        {
            "id": "whisper-large-v3-turbo",
            "name": "Whisper Large v3 Turbo",
            "size": "1.5 GB",
            "speed": 9.2,
            "accuracy": 9.8,
            "is_downloaded": true,
            "is_cloud": false,
            "category": "voice"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let model = try decoder.decode(DictyModel.self, from: json)
        
        XCTAssertEqual(model.id, "whisper-large-v3-turbo")
        XCTAssertEqual(model.name, "Whisper Large v3 Turbo")
        XCTAssertFalse(model.isTextModel)
        XCTAssertEqual(model.sizeInMB, 1.5 * 1024.0, accuracy: 0.1)
    }
    
    func testTextModelDetection() throws {
        let textModel = DictyModel(
            id: "anthropic/claude-3.5-sonnet",
            name: "Claude 3.5 Sonnet",
            size: "Cloud API",
            speed: 8.5,
            accuracy: 9.9,
            is_downloaded: true,
            is_cloud: true,
            category: "text"
        )
        XCTAssertTrue(textModel.isTextModel)
        XCTAssertEqual(textModel.sizeInMB, 0.0)
    }
    
    // MARK: - 2. Knowledge Base & Pending Updates Decoding
    
    func testPendingUpdateDecoding() throws {
        let json = """
        {
            "id": "upd_12345",
            "title": "ARCHITECTURE.md",
            "original_content": "Old content",
            "proposed_content": "# Architecture\\n\\nUpdated content...",
            "page_id": "notion_page_abc",
            "version": 1,
            "confluence_url": "https://confluence.example.com",
            "space_key": "DEV",
            "target_type": "notion",
            "timestamp": "2026-08-30 13:00:00"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let update = try decoder.decode(PendingUpdate.self, from: json)
        
        XCTAssertEqual(update.id, "upd_12345")
        XCTAssertEqual(update.title, "ARCHITECTURE.md")
        XCTAssertEqual(update.target_type, "notion")
        XCTAssertEqual(update.page_id, "notion_page_abc")
    }
    
    func testHistoryUpdateDecoding() throws {
        let json = """
        {
            "id": "hist_987",
            "title": "SYSTEM.md",
            "original_content": "Old content",
            "proposed_content": "Line 1\\nLine 2\\nLine 3",
            "target_type": "github",
            "status": "applied",
            "timestamp": "2026-08-30 13:00:00",
            "resolved_at": "2026-08-30 13:05:00"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let history = try decoder.decode(HistoryUpdate.self, from: json)
        
        XCTAssertEqual(history.id, "hist_987")
        XCTAssertEqual(history.title, "SYSTEM.md")
        XCTAssertEqual(history.target_type, "github")
        XCTAssertEqual(history.proposed_content, "Line 1\nLine 2\nLine 3")
        XCTAssertEqual(history.status, "applied")
    }
    
    // MARK: - 3. Voice Queue & Thoughts
    
    func testVoiceThoughtDecoding() throws {
        let json = """
        {
            "status": "success",
            "items": [
                {
                    "id": "vt_1",
                    "timestamp": 1788085100.0,
                    "text": "Remember to write automated tests for CI pipeline",
                    "source": "dictation",
                    "tags": ["ci", "testing"]
                }
            ],
            "count": 1
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(VoiceQueueResponse.self, from: json)
        
        XCTAssertEqual(response.status, "success")
        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.items.first?.text, "Remember to write automated tests for CI pipeline")
        XCTAssertEqual(response.items.first?.tags, ["ci", "testing"])
    }
    
    // MARK: - 4. Auth & Device Status
    
    func testAuthStatusDecoding() throws {
        let json = """
        {
            "logged_in": true,
            "email": "developer@dicty.ai",
            "is_pro": true,
            "offline_mode": false
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let auth = try decoder.decode(AuthStatusResponse.self, from: json)
        
        XCTAssertTrue(auth.logged_in)
        XCTAssertEqual(auth.email, "developer@dicty.ai")
        XCTAssertTrue(auth.is_pro)
        XCTAssertFalse(auth.offline_mode)
    }
    
    // MARK: - 5. Profile Whisper Models & Sanitization
    
    func testDefaultProfilesUseTinyWhisperModel() throws {
        let defaults = ProfileManager.defaultProfiles
        XCTAssertFalse(defaults.isEmpty)
        for profile in defaults {
            XCTAssertEqual(profile.whisperModel, "tiny", "Default profile '\(profile.name)' must use 'tiny' as default whisper model")
            XCTAssertFalse(profile.whisperModel.contains("mlx-community"), "Profile must not contain invalid mlx-community identifier")
            XCTAssertTrue(profile.keepModelInMemory, "Default profile '\(profile.name)' must have keepModelInMemory enabled")
        }
    }
    
    func testProfileManagerSanitizesLegacyInvalidModels() throws {
        let legacyProfile = DictyProfile(
            name: "Legacy Mode",
            whisperModel: "mlx-community/whisper-large-v3-turbo"
        )
        
        let encoder = JSONEncoder()
        let encoded = try encoder.encode([legacyProfile])
        UserDefaults.standard.set(encoded, forKey: "dicty_profiles_list")
        
        ProfileManager.shared.loadProfiles()
        
        let loaded = ProfileManager.shared.profiles.first(where: { $0.name == "Legacy Mode" })
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.whisperModel, "tiny", "Legacy mlx-community whisperModel must be sanitized to 'tiny'")
    }
    
    // MARK: - 6. Cross-Platform Configuration Harmonization & Sync
    
    func testWindowsBackupJSONCompatibility() throws {
        let windowsJson = """
        {
            "app": "Dicty",
            "version": "1.0.0",
            "exported_at": "2026-09-24T18:00:00.000Z",
            "vocabulary": [
                {
                    "word": "Kubernetes",
                    "replacement": "K8s"
                }
            ],
            "prompts": [
                {
                    "key": "general",
                    "value": "You are a professional assistant."
                },
                {
                    "key": "code",
                    "active_value": "Write clean and concise code."
                }
            ],
            "localStorageBackup": {
                "active_mode": "developer",
                "dictation_format_style": "markdown",
                "favorite_models": "whisper-large-v3-turbo,tiny"
            }
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(DictyConfig.self, from: windowsJson)
        
        // Vocabulary without explicit id must decode smoothly
        XCTAssertEqual(config.vocabulary.count, 1)
        XCTAssertEqual(config.vocabulary.first?.word, "Kubernetes")
        XCTAssertEqual(config.vocabulary.first?.replacement, "K8s")
        XCTAssertNil(config.vocabulary.first?.id)
        
        // Prompts with 'value' or 'active_value' must resolve correctly
        XCTAssertEqual(config.prompts.count, 2)
        let generalPrompt = config.prompts.first(where: { $0.key == "general" })
        XCTAssertEqual(generalPrompt?.resolvedValue, "You are a professional assistant.")
        let codePrompt = config.prompts.first(where: { $0.key == "code" })
        XCTAssertEqual(codePrompt?.resolvedValue, "Write clean and concise code.")
        
        // localStorageBackup cross-platform compatibility
        XCTAssertEqual(config.localStorageBackup?["active_mode"], "developer")
        XCTAssertEqual(config.localStorageBackup?["dictation_format_style"], "markdown")
    }
    
    func testMacOSBackupJSONCompatibility() throws {
        let macJson = """
        {
            "app": "Dicty",
            "version": "1.0.0",
            "exported_at": "2026-09-24T18:00:00.000Z",
            "activeMode": "coding",
            "dictationFormatStyle": "bullet_points",
            "vocabulary": [
                {
                    "id": "voc_123",
                    "word": "FastAPI",
                    "replacement": "FastAPI framework"
                }
            ],
            "prompts": [
                {
                    "key": "dictation",
                    "description": "Standard transcription prompt",
                    "default_value": "Standard",
                    "active_value": "Enhanced transcription",
                    "is_custom": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(DictyConfig.self, from: macJson)
        
        XCTAssertEqual(config.activeMode, "coding")
        XCTAssertEqual(config.dictationFormatStyle, "bullet_points")
        XCTAssertEqual(config.vocabulary.first?.id, "voc_123")
        XCTAssertEqual(config.vocabulary.first?.word, "FastAPI")
        XCTAssertEqual(config.prompts.first?.key, "dictation")
        XCTAssertEqual(config.prompts.first?.resolvedValue, "Enhanced transcription")
    }
    
    // MARK: - 7. Secrets & Update Onboarding Flow
    
    func testSecretsManagerSaveAndRead() throws {
        let testKey = "test_api_key_unit"
        let testVal = "sk-ant-test-secret-value-12345"
        
        SecretsManager.saveSecret(testVal, forKey: testKey)
        let retrieved = SecretsManager.readSecret(forKey: testKey)
        XCTAssertEqual(retrieved, testVal)
        
        // Clearing secret
        SecretsManager.saveSecret("", forKey: testKey)
        let cleared = SecretsManager.readSecret(forKey: testKey)
        XCTAssertNil(cleared)
    }
    
    func testOnboardingIsNotShownIfAlreadySeen() throws {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        XCTAssertFalse(AppDelegate.shouldPresentOnboarding(), "Onboarding must not be presented on app updates if already seen")
    }
    
    // MARK: - 8. System Audio Modes Detection
    
    func testSystemAudioModesRecognition() throws {
        XCTAssertTrue(DictyAudioRecorder.isSystemAudioMode("meeting"))
        XCTAssertTrue(DictyAudioRecorder.isSystemAudioMode("focused_meeting"))
        XCTAssertFalse(DictyAudioRecorder.isSystemAudioMode("librarian"))
        XCTAssertFalse(DictyAudioRecorder.isSystemAudioMode("dictation"))
        XCTAssertFalse(DictyAudioRecorder.isSystemAudioMode("general"))
    }
    
    // MARK: - 9. Safe Resource Loading & Flag Normalization
    
    func testDictyResourcesMissingFileReturnsNilWithoutCrash() throws {
        // Must safely return nil rather than triggering SPM's fatalError assertion
        let nonExistentURL = DictyResources.url(forResource: "non_existent_asset_xyz", withExtension: "png")
        XCTAssertNil(nonExistentURL)
        
        let nonExistentPath = DictyResources.path(forResource: "non_existent_asset_xyz", ofType: "png")
        XCTAssertNil(nonExistentPath)
        
        let nonExistentImage = DictyResources.image(named: "non_existent_asset_xyz")
        XCTAssertNil(nonExistentImage)
    }
    
    func testCountryCodeNormalization() throws {
        XCTAssertEqual(CountryFlagView.normalizeCode("🇺🇸"), "us")
        XCTAssertEqual(CountryFlagView.normalizeCode("🇬🇧"), "gb")
        XCTAssertEqual(CountryFlagView.normalizeCode("🇩🇪"), "de")
        XCTAssertEqual(CountryFlagView.normalizeCode("🇷🇺"), "ru")
        XCTAssertEqual(CountryFlagView.normalizeCode("🇪🇸"), "es")
        XCTAssertEqual(CountryFlagView.normalizeCode("🇺🇦"), "ua")
        XCTAssertEqual(CountryFlagView.normalizeCode("🌐"), "all")
        
        XCTAssertEqual(CountryFlagView.normalizeCode("en-US"), "us")
        XCTAssertEqual(CountryFlagView.normalizeCode("en-GB"), "gb")
        XCTAssertEqual(CountryFlagView.normalizeCode("de-DE"), "de")
        XCTAssertEqual(CountryFlagView.normalizeCode("multilingual"), "all")
        XCTAssertEqual(CountryFlagView.normalizeCode("global"), "all")
    }
    
    func testCountryFlagViewBodyEvaluationDoesNotCrash() throws {
        // Instantiate CountryFlagView with various codes and evaluate body
        let codes = ["us", "gb", "de", "ru", "es", "ua", "all", "unknown_xx"]
        for code in codes {
            let view = CountryFlagView(code)
            _ = view.body
        }
    }

    func testModelFamilyLanguageVariantSelection() throws {
        let tinyEn = DictyModel(id: "tiny.en", name: "Nano", size: "31 MB", speed: 1.0, accuracy: 0.4, is_downloaded: true, is_cloud: false)
        let tiny = DictyModel(id: "tiny", name: "Nano", size: "31 MB", speed: 1.0, accuracy: 0.4, is_downloaded: true, is_cloud: false)
        let models = [tinyEn, tiny]
        
        let family = ModelFamily(id: "nano", name: "Nano", bestFor: "Quick notes, any Mac", enModelId: "tiny.en", multiModelId: "tiny")
        
        // English prefers .en
        let enPref = family.preferredVariant(for: "en", models: models)
        XCTAssertEqual(enPref?.id, "tiny.en")
        
        // Russian / Auto / Other prefers multilingual
        let ruPref = family.preferredVariant(for: "ru", models: models)
        XCTAssertEqual(ruPref?.id, "tiny")
        
        let autoPref = family.preferredVariant(for: "auto", models: models)
        XCTAssertEqual(autoPref?.id, "tiny")
    }
    
    func testModelFamilySingleVariantHandling() throws {
        let turbo = DictyModel(id: "large-v3-turbo", name: "Turbo", size: "547 MB", speed: 0.8, accuracy: 0.98, is_downloaded: true, is_cloud: false)
        let distil = DictyModel(id: "distil-large-v3", name: "Turbo (Distil)", size: "1.5 GB", speed: 1.0, accuracy: 0.98, is_downloaded: true, is_cloud: false)
        let models = [turbo, distil]
        
        let turboFamily = ModelFamily(id: "turbo", name: "Turbo", bestFor: "Best quality on fast Macs", enModelId: nil, multiModelId: "large-v3-turbo")
        XCTAssertEqual(turboFamily.preferredVariant(for: "en", models: models)?.id, "large-v3-turbo")
        XCTAssertEqual(turboFamily.preferredVariant(for: "ru", models: models)?.id, "large-v3-turbo")
        
        let distilFamily = ModelFamily(id: "distil-turbo", name: "Turbo (Distil)", bestFor: "Fast high-accuracy English", enModelId: "distil-large-v3", multiModelId: nil)
        XCTAssertEqual(distilFamily.preferredVariant(for: "en", models: models)?.id, "distil-large-v3")
        XCTAssertEqual(distilFamily.preferredVariant(for: "ru", models: models)?.id, "distil-large-v3")
    }

    // MARK: - 10. Model Language Filtering & Auto-fallback

    func testModelLanguageFilterVisibilityAndFallback() throws {
        // Distil is English-only
        let distilFamily = ModelFamily(id: "distil-turbo", name: "Turbo (Distil)", bestFor: "Fast high-accuracy English", enModelId: "distil-large-v3", multiModelId: nil)
        let turboFamily = ModelFamily(id: "turbo", name: "Turbo", bestFor: "Best quality on fast Macs", enModelId: nil, multiModelId: "large-v3-turbo")

        // 1. English language: Distil is visible
        XCTAssertTrue(ModelLanguageFilter.isEnglish("en"))
        XCTAssertTrue(ModelLanguageFilter.isEnglish("en-US"))
        XCTAssertFalse(ModelLanguageFilter.isEnglish("auto"))
        XCTAssertFalse(ModelLanguageFilter.isEnglish("es"))
        XCTAssertFalse(ModelLanguageFilter.isEnglish("de"))

        XCTAssertTrue(ModelLanguageFilter.isModelFamilyVisible(distilFamily, for: "en"))
        XCTAssertTrue(ModelLanguageFilter.isModelFamilyVisible(distilFamily, for: "en-US"))

        // 2. Non-English (Auto Detect or foreign): Distil is hidden
        XCTAssertFalse(ModelLanguageFilter.isModelFamilyVisible(distilFamily, for: "auto"))
        XCTAssertFalse(ModelLanguageFilter.isModelFamilyVisible(distilFamily, for: "ru"))
        XCTAssertFalse(ModelLanguageFilter.isModelFamilyVisible(distilFamily, for: "de"))

        // Turbo (multilingual) remains visible for both
        XCTAssertTrue(ModelLanguageFilter.isModelFamilyVisible(turboFamily, for: "en"))
        XCTAssertTrue(ModelLanguageFilter.isModelFamilyVisible(turboFamily, for: "auto"))
        XCTAssertTrue(ModelLanguageFilter.isModelFamilyVisible(turboFamily, for: "es"))

        // 3. Fallback check when switching from English to Auto Detect with Distil active
        let fallbackAuto = ModelLanguageFilter.checkLanguageSwitchFallback(
            from: "en",
            to: "auto",
            activeModelId: "distil-large-v3"
        )
        XCTAssertNotNil(fallbackAuto)
        XCTAssertEqual(fallbackAuto?.fallbackModelId, "large-v3-turbo")
        XCTAssertEqual(fallbackAuto?.noticeMessage, "Switched to Turbo because Turbo (Distil) only supports English.")

        // 4. Fallback check when switching to German
        let fallbackDe = ModelLanguageFilter.checkLanguageSwitchFallback(
            from: "en",
            to: "de",
            activeModelId: "distil-large-v3"
        )
        XCTAssertNotNil(fallbackDe)
        XCTAssertEqual(fallbackDe?.fallbackModelId, "large-v3-turbo")

        // 5. Switching within English should NOT trigger fallback
        let fallbackEn = ModelLanguageFilter.checkLanguageSwitchFallback(
            from: "en",
            to: "en-US",
            activeModelId: "distil-large-v3"
        )
        XCTAssertNil(fallbackEn)

        // 6. Switching when a non-Distil model is active should NOT trigger fallback
        let fallbackOther = ModelLanguageFilter.checkLanguageSwitchFallback(
            from: "en",
            to: "auto",
            activeModelId: "large-v3-turbo"
        )
        XCTAssertNil(fallbackOther)
    }

    // MARK: - 11. Modifier Shortcut Press/Release Detection
    func testModifierShortcutPressDetection() {
        // Test Right Option (keyCode 61) modifier state
        let optionFlags = NSEvent.ModifierFlags.option
        let emptyFlags = NSEvent.ModifierFlags()
        
        // 1. Physical down check
        XCTAssertTrue(EngineClient.isModifierDown(keyCode: 61, flags: optionFlags))
        XCTAssertFalse(EngineClient.isModifierDown(keyCode: 61, flags: emptyFlags))
        
        // 2. Press logic when targetModifiers is empty (single modifier key, e.g. Right Option alone)
        let targetModifiers = NSEvent.ModifierFlags()
        
        // When pressed down:
        let isDownWhenPressed = EngineClient.isModifierDown(keyCode: 61, flags: optionFlags)
        let isPressedWhenPressed = isDownWhenPressed && (targetModifiers.isEmpty || optionFlags.contains(targetModifiers))
        XCTAssertTrue(isPressedWhenPressed, "Modifier key must be evaluated as pressed when down")
        
        // When released:
        let isDownWhenReleased = EngineClient.isModifierDown(keyCode: 61, flags: emptyFlags)
        let isPressedWhenReleased = isDownWhenReleased && (targetModifiers.isEmpty || emptyFlags.contains(targetModifiers))
        XCTAssertFalse(isPressedWhenReleased, "Modifier key must NOT be evaluated as pressed when released")
    }

    // MARK: - 11. Acceptance Criteria Screenshot Capture

    func testCapturePolishScreenshots() throws {
        let artifactDir = "/Users/vasiliikazmin/.gemini/antigravity-ide/brain/5703cfeb-27e5-452f-accf-2bca5e0b6147"
        let engineClient = EngineClient.shared
        
        // Mock sample OpenRouter models for Explorer screenshot
        engineClient.openRouterModels = [
            OpenRouterModelInfo(
                id: "meta-llama/llama-3.3-70b-instruct:free",
                name: "Meta: Llama 3.3 70B Instruct (free)",
                description: "A high-performance open model by Meta with strong reasoning and coding capabilities.",
                context_length: 131072,
                prompt_price_per_m: 0.0,
                completion_price_per_m: 0.0
            ),
            OpenRouterModelInfo(
                id: "google/gemini-2.0-flash-exp:free",
                name: "Google: Gemini 2.0 Flash Experimental (free)",
                description: "Google next-generation lightweight model built for multimodal speed and low latency.",
                context_length: 1048576,
                prompt_price_per_m: 0.0,
                completion_price_per_m: 0.0
            ),
            OpenRouterModelInfo(
                id: "deepseek/deepseek-chat:free",
                name: "DeepSeek: DeepSeek V3 (free)",
                description: "DeepSeek general chat and reasoning model delivering competitive speed.",
                context_length: 65536,
                prompt_price_per_m: 0.0,
                completion_price_per_m: 0.0
            ),
            OpenRouterModelInfo(
                id: "deepseek/deepseek-r1:free",
                name: "DeepSeek: DeepSeek R1 (free)",
                description: "First-generation reasoning model trained via reinforcement learning for logic problems.",
                context_length: 65536,
                prompt_price_per_m: 0.0,
                completion_price_per_m: 0.0
            )
        ]
        
        engineClient.models = [
            DictyModel(id: "tiny.en", name: "Tiny (English)", size: "75 MB", speed: 0.98, accuracy: 0.65, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "tiny", name: "Tiny (Multilingual)", size: "75 MB", speed: 0.95, accuracy: 0.60, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "base.en", name: "Base (English)", size: "142 MB", speed: 0.88, accuracy: 0.75, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "base", name: "Base (Multilingual)", size: "142 MB", speed: 0.85, accuracy: 0.70, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "small.en", name: "Small (English)", size: "466 MB", speed: 0.68, accuracy: 0.85, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "small", name: "Small (Multilingual)", size: "466 MB", speed: 0.65, accuracy: 0.82, is_downloaded: false, is_cloud: false, category: "voice"),
            DictyModel(id: "medium.en", name: "Medium (English)", size: "514 MB", speed: 0.45, accuracy: 0.92, is_downloaded: false, is_cloud: false, category: "voice"),
            DictyModel(id: "medium", name: "Medium (Multilingual)", size: "1.5 GB", speed: 0.40, accuracy: 0.90, is_downloaded: false, is_cloud: false, category: "voice"),
            DictyModel(id: "large-v3-turbo", name: "Turbo", size: "1.5 GB", speed: 0.80, accuracy: 0.90, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "large-v3", name: "Large v3", size: "3.1 GB", speed: 0.25, accuracy: 0.98, is_downloaded: false, is_cloud: false, category: "voice"),
        ]
        engineClient.activeModel = "small.en"
        
        let accents = ["slate", "lavender"]
        let modes: [(isDark: Bool, name: String)] = [(false, "light"), (true, "dark")]
        
        func renderToFile<V: View>(_ view: V, width: CGFloat, height: CGFloat, isDark: Bool, filename: String) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            let hosting = NSHostingView(rootView: view.environment(\.colorScheme, isDark ? .dark : .light).environmentObject(engineClient))
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.appearance = window.appearance
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    let fileURL = URL(fileURLWithPath: "\(artifactDir)/\(filename)")
                    try? png.write(to: fileURL)
                }
            }
        }
        
        for accent in accents {
            UserDefaults.standard.set(accent, forKey: "appAccentColor")
            NotificationCenter.default.post(name: .dictyAccentColorDidChange, object: nil)
            
            for (isDark, modeName) in modes {
                // 1. Model Explorer (Free filter on, Active row)
                var activeModel = "meta-llama/llama-3.3-70b-instruct:free"
                let explorer = OpenRouterModelExplorerSheet(
                    selectedModel: Binding(get: { activeModel }, set: { activeModel = $0 }),
                    initialProvider: "Free"
                )
                renderToFile(explorer, width: 740, height: 600, isDark: isDark, filename: "model_explorer_\(accent)_\(modeName).png")
                
                // 2. Models with Auto Detect
                engineClient.transcriptionLanguage = "auto"
                let modelsAuto = ModelsLibraryView()
                renderToFile(modelsAuto, width: 920, height: 650, isDark: isDark, filename: "models_auto_\(accent)_\(modeName).png")
                
                // 3. Models at minimum window width
                renderToFile(modelsAuto, width: 780, height: 600, isDark: isDark, filename: "models_minwidth_\(accent)_\(modeName).png")
                
                // 4. Projects
                let projects = ProjectsView()
                renderToFile(projects, width: 800, height: 600, isDark: isDark, filename: "projects_\(accent)_\(modeName).png")
                
                // 5. Focused Meeting (app picker)
                let appPicker = AppSelectionView()
                renderToFile(appPicker, width: 700, height: 600, isDark: isDark, filename: "focused_meeting_\(accent)_\(modeName).png")
                
                // 6. Settings -> General
                let general = PreferencesSettingsView()
                renderToFile(general, width: 800, height: 700, isDark: isDark, filename: "settings_general_\(accent)_\(modeName).png")
                
                // 7. Settings -> Shortcuts (permission granted & missing)
                let shortcutsGranted = ShortcutsView(overrideAccessibilityPermission: true)
                renderToFile(shortcutsGranted, width: 800, height: 650, isDark: isDark, filename: "settings_shortcuts_granted_\(accent)_\(modeName).png")
                
                let shortcutsMissing = ShortcutsView(overrideAccessibilityPermission: false)
                renderToFile(shortcutsMissing, width: 800, height: 650, isDark: isDark, filename: "settings_shortcuts_missing_\(accent)_\(modeName).png")
            }
        }
    }

    func testCaptureTranslationAndAILocationScreenshots() throws {
        let artifactDir = "/Users/vasiliikazmin/.gemini/antigravity-ide/brain/b94c08e7-e91e-4ea1-aa51-1c7f82ae4487"
        let engineClient = EngineClient.shared
        
        engineClient.models = [
            DictyModel(id: "base.en", name: "Base", size: "142 MB", speed: 0.88, accuracy: 0.75, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "small.en", name: "Fast", size: "466 MB", speed: 0.68, accuracy: 0.85, is_downloaded: true, is_cloud: false, category: "voice"),
            DictyModel(id: "qwen3.5-0.8b", name: "Qwen 3.5 0.8B", size: "600 MB", speed: 0.95, accuracy: 0.80, is_downloaded: true, is_cloud: false, category: "text"),
            DictyModel(id: "deepseek/deepseek-v4-flash", name: "DeepSeek V4 Flash", size: "Cloud API", speed: 1.0, accuracy: 0.95, is_downloaded: false, is_cloud: true, category: "text"),
        ]
        engineClient.activeModel = "small.en"
        engineClient.activeTextModel = "qwen3.5-0.8b"
        
        func renderToFile<V: View>(_ view: V, width: CGFloat, height: CGFloat, isDark: Bool, filename: String) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            let hosting = NSHostingView(rootView: view.background(Color(NSColor.windowBackgroundColor)).environment(\.colorScheme, isDark ? .dark : .light).environmentObject(engineClient))
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.appearance = window.appearance
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    let fileURL = URL(fileURLWithPath: "\(artifactDir)/\(filename)")
                    try? png.write(to: fileURL)
                }
            }
        }
        
        // 1. Language Picker Sheet (Translate to default view)
        let picker = LanguagePickerSheet(mode: .translationTarget, currentCode: "de", onSelect: { _ in })
        renderToFile(picker, width: 380, height: 480, isDark: true, filename: "translate_picker_dark.png")
        renderToFile(picker, width: 380, height: 480, isDark: false, filename: "translate_picker_light.png")

        // 1b. Language Picker Sheet (Translate to with search query "Ger")
        let pickerSearch = LanguagePickerSheet(mode: .translationTarget, currentCode: "de", initialSearchText: "Ger", onSelect: { _ in })
        renderToFile(pickerSearch, width: 380, height: 480, isDark: true, filename: "translate_picker_search_dark.png")
        renderToFile(pickerSearch, width: 380, height: 480, isDark: false, filename: "translate_picker_search_light.png")

        // 2. AI Location Card: On this Mac
        engineClient.activeModel = "base"
        UserDefaults.standard.set("local", forKey: "llmProvider")
        UserDefaults.standard.set("qwen3.5-0.8b", forKey: "llmModel")
        let storeLocal = ModesStore()
        storeLocal.capabilities = Capabilities(
            aiLocation: "local",
            correctionLocation: "local_rules",
            localTextModels: ["qwen3.5-0.8b"],
            cloudAccess: true,
            modes: []
        )
        let cardLocal = AILocationCard(store: storeLocal, modelsInUse: engineClient.models)
            .padding(20)
            .frame(width: 700)
        renderToFile(cardLocal, width: 700, height: 320, isDark: true, filename: "ai_location_on_this_mac_dark.png")
        renderToFile(cardLocal, width: 700, height: 320, isDark: false, filename: "ai_location_on_this_mac_light.png")

        // 3. AI Location Card: Cloud
        _ = SecretsManager.saveSecret("mock-cloud-key", forKey: "llmApiKey")
        engineClient.activeModel = "deepgram/nova-3"
        UserDefaults.standard.set("openrouter", forKey: "llmProvider")
        UserDefaults.standard.set("deepseek/deepseek-v4-flash", forKey: "llmModel")
        let storeCloud = ModesStore()
        storeCloud.capabilities = Capabilities(
            aiLocation: "cloud_when_better",
            correctionLocation: "cloud",
            localTextModels: ["qwen3.5-0.8b"],
            cloudAccess: true,
            modes: []
        )
        let cardCloud = AILocationCard(store: storeCloud, modelsInUse: engineClient.models)
            .padding(20)
            .frame(width: 700)
        renderToFile(cardCloud, width: 700, height: 320, isDark: true, filename: "ai_location_cloud_when_better_dark.png")
        renderToFile(cardCloud, width: 700, height: 320, isDark: false, filename: "ai_location_cloud_when_better_light.png")

        // 3b. AI Location Card: Custom (Local voice + Cloud text)
        engineClient.activeModel = "base"
        let cardCustom = AILocationCard(store: storeCloud, modelsInUse: engineClient.models)
            .padding(20)
            .frame(width: 700)
        renderToFile(cardCustom, width: 700, height: 320, isDark: true, filename: "ai_location_custom_dark.png")
        renderToFile(cardCustom, width: 700, height: 320, isDark: false, filename: "ai_location_custom_light.png")

        // 4. Header Language Bar
        let modelsView = ModelsLibraryView()
        renderToFile(modelsView, width: 850, height: 200, isDark: true, filename: "models_header_language_bar_dark.png")
        renderToFile(modelsView, width: 850, height: 200, isDark: false, filename: "models_header_language_bar_light.png")

        // 5. Mode Detail with Translate to card & under 2B notice
        var testProfile = ProfileManager.shared.profiles.first ?? DictyProfile(id: UUID(), name: "Email", icon: "envelope.fill", activeMode: "general", whisperModel: "small")
        testProfile.targetLanguage = "de"
        let modeDetail = ModeDetailView(
            profile: testProfile,
            isActive: true,
            store: storeLocal,
            onBack: {},
            onActivate: {},
            onUpdate: { _ in },
            onDelete: {}
        )
        renderToFile(modeDetail, width: 700, height: 600, isDark: true, filename: "mode_detail_translate_under2b_dark.png")
        renderToFile(modeDetail, width: 700, height: 600, isDark: false, filename: "mode_detail_translate_under2b_light.png")
    }

    // MARK: - 7. Engine Endpoint Auth Contract

    func testEngineTokenRejectionDetection() {
        XCTAssertTrue(EngineEndpoint.shared.isTokenRejection(
            data: Data(#"{"error":"unauthorized"}"#.utf8)
        ))
        XCTAssertFalse(EngineEndpoint.shared.isTokenRejection(
            data: Data(#"{"detail":"Invalid credentials"}"#.utf8)
        ))
        XCTAssertFalse(EngineEndpoint.shared.isTokenRejection(data: nil))
        XCTAssertFalse(EngineEndpoint.shared.isTokenRejection(
            data: Data("not json".utf8)
        ))
    }

    func testEngineEndpointURLsAreLoopbackOnly() {
        XCTAssertEqual(
            EngineEndpoint.shared.url("/models").absoluteString,
            "http://127.0.0.1:8075/models"
        )
        XCTAssertEqual(
            EngineEndpoint.shared.url("/search", query: ["b": "2", "a": "1"]).absoluteString,
            "http://127.0.0.1:8075/search?a=1&b=2"
        )
        XCTAssertEqual(
            EngineEndpoint.shared.webSocketURL("/ws/transcribe/stream").absoluteString,
            "ws://127.0.0.1:8075/ws/transcribe/stream"
        )
    }

    // MARK: - 8. Target App Context

    func testTargetAppContextSanitizesAndBuildsFormFields() {
        let context = TargetAppContext(name: "  Slack\n", bundleID: "com.tinyspeck.slackmacgap\r")
        XCTAssertEqual(context?.name, "Slack")
        XCTAssertEqual(context?.bundleID, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(context?.formFields.map { $0.name }, ["target_app_name", "target_app_bundle_id"])
        XCTAssertEqual(context?.formFields.map { $0.value }, ["Slack", "com.tinyspeck.slackmacgap"])
    }

    func testTargetAppContextRejectsEmptyMetadata() {
        XCTAssertNil(TargetAppContext(name: " \n ", bundleID: "\r"))
        XCTAssertNil(TargetAppContext(application: nil))
    }

    // MARK: - 9. App Rules Models & History Metadata
    
    func testAppRulesResponseDecoding() throws {
        let json = """
        {
            "settings": {
                "enabled": true,
                "override_scope": "recording"
            },
            "rules": [
                {
                    "id": "rule_slack",
                    "match": {
                        "type": "bundle_id",
                        "value": "com.tinyspeck.slackmacgap"
                    },
                    "mode_id": "message",
                    "display_name": "Slack",
                    "enabled": true,
                    "is_default": true,
                    "overridden": false
                }
            ]
        }
        """.data(using: .utf8)!
        
        let resp = try JSONDecoder().decode(AppRulesResponse.self, from: json)
        XCTAssertTrue(resp.settings.enabled)
        XCTAssertEqual(resp.settings.override_scope, "recording")
        XCTAssertEqual(resp.rules.count, 1)
        XCTAssertEqual(resp.rules[0].id, "rule_slack")
        XCTAssertEqual(resp.rules[0].match.type, "bundle_id")
        XCTAssertEqual(resp.rules[0].match.value, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(resp.rules[0].mode_id, "message")
        XCTAssertEqual(resp.rules[0].display_name, "Slack")
        XCTAssertTrue(resp.rules[0].enabled)
        XCTAssertTrue(resp.rules[0].is_default)
    }
    
    func testAppRuleResolveResponseDecoding() throws {
        let json = """
        {
            "resolved_mode": "message",
            "reason": "app_rule",
            "rule_id": "rule_slack",
            "app_id": "com.tinyspeck.slackmacgap"
        }
        """.data(using: .utf8)!
        
        let resp = try JSONDecoder().decode(AppRuleResolveResponse.self, from: json)
        XCTAssertEqual(resp.resolved_mode, "message")
        XCTAssertEqual(resp.reason, "app_rule")
        XCTAssertEqual(resp.rule_id, "rule_slack")
        XCTAssertEqual(resp.app_id, "com.tinyspeck.slackmacgap")
    }
    
    func testDictyHistoryWithAppMetadataDecoding() throws {
        let json = """
        {
            "id": "hist_123",
            "timestamp": "2026-10-23T10:00:00Z",
            "text": "Hello team, standup at 11.",
            "mode": "dictation",
            "audio_file": "audio_123.wav",
            "app_id": "com.tinyspeck.slackmacgap",
            "app_name": "Slack",
            "mode_id": "message",
            "mode_reason": "app_rule"
        }
        """.data(using: .utf8)!
        
        let record = try JSONDecoder().decode(DictyHistory.self, from: json)
        XCTAssertEqual(record.id, "hist_123")
        XCTAssertEqual(record.app_id, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(record.app_name, "Slack")
        XCTAssertEqual(record.mode_id, "message")
        XCTAssertEqual(record.mode_reason, "app_rule")
    }
    
    func testAvailableAppRuleModesExcludeMeetingModes() {
        let modeIds = Set(availableAppRuleModes.map { $0.id })
        XCTAssertTrue(modeIds.contains("dictation"))
        XCTAssertTrue(modeIds.contains("message"))
        XCTAssertTrue(modeIds.contains("email"))
        XCTAssertTrue(modeIds.contains("code"))
        XCTAssertTrue(modeIds.contains("note"))
        XCTAssertTrue(modeIds.contains("book"))
        XCTAssertTrue(modeIds.contains("issue"))
        XCTAssertTrue(modeIds.contains("librarian"))
        
        // Strict invariant: Meeting modes must NEVER be app rule targets
        XCTAssertFalse(modeIds.contains("meeting"))
        XCTAssertFalse(modeIds.contains("focused_meeting"))
    }
    
    // MARK: - 11. Phase 3: Learning Suggestion Tests
    
    func testAppRuleSuggestionDecodingAndEncoding() throws {
        let json = """
        {
            "app_id": "com.apple.mobilesms",
            "app_name": "Messages",
            "mode_id": "note",
            "count": 2
        }
        """.data(using: .utf8)!
        
        let suggestion = try JSONDecoder().decode(AppRuleSuggestion.self, from: json)
        XCTAssertEqual(suggestion.app_id, "com.apple.mobilesms")
        XCTAssertEqual(suggestion.app_name, "Messages")
        XCTAssertEqual(suggestion.mode_id, "note")
        XCTAssertEqual(suggestion.count, 2)
        
        let encoded = try JSONEncoder().encode(suggestion)
        let decodedAgain = try JSONDecoder().decode(AppRuleSuggestion.self, from: encoded)
        XCTAssertEqual(suggestion, decodedAgain)
    }
    
    @MainActor
    func testEngineClientAppRuleSuggestionFlow() {
        let client = EngineClient.shared
        let suggestion = AppRuleSuggestion(app_id: "com.apple.mobilesms", app_name: "Messages", mode_id: "note", count: 2)
        
        client.presentAppRuleSuggestion(suggestion)
        XCTAssertEqual(client.pendingAppRuleSuggestion, suggestion)
        
        client.dismissAppRuleSuggestion()
        XCTAssertNil(client.pendingAppRuleSuggestion)
    }
    
    func testOpenRouterSortOptionsAndModelExtensions() {
        XCTAssertEqual(OpenRouterSortOption.allCases.count, 6)
        XCTAssertEqual(OpenRouterSortOption.mostPopular.rawValue, "most-popular")
        XCTAssertEqual(OpenRouterSortOption.throughputHighToLow.rawValue, "throughput-high-to-low")
        XCTAssertEqual(OpenRouterSortOption.throughputLowToHigh.rawValue, "throughput-low-to-high")
        XCTAssertEqual(OpenRouterSortOption.latencyLowToHigh.rawValue, "latency-low-to-high")
        XCTAssertEqual(OpenRouterSortOption.priceLowToHigh.rawValue, "pricing-low-to-high")
        XCTAssertEqual(OpenRouterSortOption.priceHighToLow.rawValue, "pricing-high-to-low")
        
        let freeModel = OpenRouterModelInfo(
            id: "deepseek/deepseek-chat:free",
            name: "DeepSeek: DeepSeek V3 (free)",
            description: "Fast model",
            context_length: 64000,
            prompt_price_per_m: 0.0,
            completion_price_per_m: 0.0
        )
        XCTAssertTrue(freeModel.isFree)
        XCTAssertEqual(freeModel.cleanDisplayName, "DeepSeek V3 (free)")
        XCTAssertEqual(freeModel.providerName, "DeepSeek")
        XCTAssertEqual(freeModel.priceText, "Free")
        
        let paidModel = OpenRouterModelInfo(
            id: "openai/gpt-4o-mini",
            name: "OpenAI: GPT-4o-mini",
            description: "High speed",
            context_length: 128000,
            prompt_price_per_m: 0.15,
            completion_price_per_m: 0.60
        )
        XCTAssertFalse(paidModel.isFree)
        XCTAssertTrue(paidModel.isFast)
        XCTAssertEqual(paidModel.cleanDisplayName, "GPT-4o-mini")
        XCTAssertEqual(paidModel.providerName, "OpenAI")
        XCTAssertEqual(paidModel.priceText, "$0.15 in · $0.60 out per 1M tokens")
    }
    
    func testLocalLLMAddonStatusDecoding() throws {
        let json = """
        {
            "installed": true,
            "running": true,
            "stage": "ready",
            "progress": 1.0,
            "downloaded_bytes": 1045000000,
            "total_bytes": 1045000000,
            "error": null,
            "disk_usage_bytes": 1045000000,
            "model_id": "qwen2.5-1.5b-instruct",
            "model_name": "Qwen 2.5 1.5B Instruct"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let status = try decoder.decode(LocalLLMAddonStatus.self, from: json)
        XCTAssertTrue(status.installed)
        XCTAssertTrue(status.running)
        XCTAssertEqual(status.stage, "ready")
        XCTAssertEqual(status.progress, 1.0)
        XCTAssertEqual(status.model_id, "qwen2.5-1.5b-instruct")
        XCTAssertEqual(status.model_name, "Qwen 2.5 1.5B Instruct")
        XCTAssertNil(status.error)
    }
}
#endif

