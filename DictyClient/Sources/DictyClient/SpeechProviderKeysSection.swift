import SwiftUI

/// "Cloud Transcription" section on the API Keys page: bring-your-own keys for
/// speech-to-text providers. Keys live in the macOS Keychain and are handed to the
/// local engine in memory only. With a key, Dicty calls that provider directly
/// (lowest latency, billed to you) instead of routing through Dicty Cloud / OpenRouter.
struct SpeechProviderKeysSection: View {
    @EnvironmentObject var engineClient: EngineClient

    private struct Provider: Identifiable {
        let id: String           // engine provider id
        let keychainKey: String
        let name: String
        let placeholder: String
        let models: String
        let consoleURL: String
    }

    private let providers: [Provider] = [
        Provider(id: "deepgram", keychainKey: "deepgramApiKey", name: "Deepgram",
                 placeholder: "Deepgram API key", models: "Nova 3",
                 consoleURL: "https://console.deepgram.com"),
        Provider(id: "groq", keychainKey: "groqApiKey", name: "Groq",
                 placeholder: "gsk_...", models: "Whisper Large v3 Turbo",
                 consoleURL: "https://console.groq.com/keys"),
        Provider(id: "elevenlabs", keychainKey: "elevenlabsApiKey", name: "ElevenLabs",
                 placeholder: "sk_...", models: "Scribe v2",
                 consoleURL: "https://elevenlabs.io/app/settings/api-keys"),
        Provider(id: "openai", keychainKey: "openaiApiKey", name: "OpenAI",
                 placeholder: "sk-proj-...", models: "Whisper-1",
                 consoleURL: "https://platform.openai.com/api-keys"),
    ]

    @AppStorage("cloudStreaming") private var cloudStreaming = true
    @State private var values: [String: String] = [:]
    @State private var configured: [String: Bool] = [:]
    @State private var savedFlash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.appAccent)
                Text("Cloud Transcription (Bring Your Own Key)")
                    .font(.headline)
            }
            Text("Add a key to use that provider's speech models with your own account. Dicty then calls the provider directly, which is faster than routing through Dicty Cloud or OpenRouter. Keys are stored in your macOS Keychain. Select the model itself in the Models Library.")
                .font(.caption)
                .foregroundColor(.dictySecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $cloudStreaming) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcribe while I speak")
                        .font(.system(size: 13, weight: .medium))
                    Text("Cloud models start transcribing while you talk, so results come faster. Local models wait until you stop.")
                        .font(.system(size: 11))
                        .foregroundColor(.dictySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.appAccent)
            .padding(.bottom, 4)

            ForEach(providers) { p in
                providerRow(p)
            }
        }
        .onAppear {
            for p in providers {
                values[p.id] = SecretsManager.readSecret(forKey: p.keychainKey) ?? ""
            }
            Task { configured = await engineClient.pushSTTProviderKeys() }
        }
    }

    private func providerRow(_ p: Provider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                getProviderIcon(for: p.id, size: 14)
                Text(p.name).font(.subheadline).fontWeight(.medium)
                Text("· \(p.models)").font(.caption).foregroundColor(.dictySecondary)
                Spacer()
                statusBadge(for: p)
                if let url = URL(string: p.consoleURL) {
                    Link("Get key", destination: url)
                        .font(.caption)
                        .foregroundColor(Color.appAccent)
                }
            }
            HStack {
                SecureField(p.placeholder, text: Binding(
                    get: { values[p.id] ?? "" },
                    set: { values[p.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Button("Save") { save(p) }
            }
            if savedFlash == p.id {
                Text((values[p.id] ?? "").isEmpty ? "Removed." : "Saved. \(p.models) will use your \(p.name) key.")
                    .foregroundColor(Color.appAccent).font(.caption)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func statusBadge(for p: Provider) -> some View {
        if configured[p.id] == true {
            Text("Active")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.appAccent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.appAccent.opacity(0.15))
                .cornerRadius(4)
        }
    }

    private func save(_ p: Provider) {
        let value = (values[p.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        values[p.id] = value
        SecretsManager.saveSecret(value, forKey: p.keychainKey)
        Task {
            configured = await engineClient.pushSTTProviderKeys()
            savedFlash = p.id
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if savedFlash == p.id { savedFlash = nil }
        }
    }
}
