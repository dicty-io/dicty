import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Transcribe Local File

struct TranscribeFileView: View {
    @EnvironmentObject var engineClient: EngineClient
    
    @State private var isTargeted = false
    @State private var targetModel = ""
    @State private var language = "auto"
    @State private var targetLanguage = "none"
    
    private var isEnglishOnly: Bool {
        let currentModelId = targetModel.isEmpty ? engineClient.activeModel : targetModel
        return currentModelId.hasSuffix(".en") || currentModelId == "distil-large-v3"
    }

    private var whisperLanguages: [(name: String, code: String)] {
        LanguageCatalog.allLanguages.map { ($0.displayName, $0.code) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Transcribe Local File")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                FeatureHelpButton(topic: .transcribe)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
            .padding(.horizontal, 40)
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Model Override:")
                                .frame(width: 120, alignment: .trailing)
                            FixedWidthPicker(
                                selection: $targetModel,
                                width: 250,
                                label: {
                                    if let model = engineClient.models.first(where: { $0.id == targetModel }) {
                                        if model.is_cloud == true {
                                            Text("\(Image(systemName: "cloud")) \(model.name)")
                                        } else if model.is_downloaded == true {
                                            Text("\(Image(systemName: "externaldrive")) \(model.name)")
                                        } else {
                                            Text("\(Image(systemName: "arrow.down.circle.dotted")) \(model.name)")
                                        }
                                    } else {
                                        Text("Use Active System Model")
                                    }
                                }
                            ) {
                                Text("Use Active System Model").tag("")
                                ForEach(engineClient.models.sorted { a, b in
                                    let aIsCloud = a.is_cloud == true
                                    let bIsCloud = b.is_cloud == true
                                    if aIsCloud == bIsCloud {
                                        return a.name < b.name
                                    }
                                    return !aIsCloud
                                }) { model in
                                    if model.is_cloud == true {
                                        Text("\(Image(systemName: "cloud")) \(model.name)").tag(model.id)
                                    } else if model.is_downloaded == true {
                                        Text("\(Image(systemName: "externaldrive")) \(model.name)").tag(model.id)
                                    } else {
                                        Text("\(Image(systemName: "arrow.down.circle.dotted")) \(model.name)").tag(model.id)
                                    }
                                }
                            }
                            .disabled(engineClient.transcribeFileIsProcessing)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Language:")
                                    .frame(width: 120, alignment: .trailing)
                                
                                FixedWidthPicker(
                                    selection: $language,
                                    width: 250,
                                    label: { Text(whisperLanguages.first { $0.code == language }?.name ?? "Auto Detect") }
                                ) {
                                    ForEach(whisperLanguages, id: \.code) { lang in
                                        Text(lang.name).tag(lang.code)
                                    }
                                }
                                .disabled(engineClient.transcribeFileIsProcessing || isEnglishOnly)
                            }
                            
                            if isEnglishOnly {
                                Text("(English-only model)")
                                    .font(.caption)
                                    .foregroundColor(.dictySecondary)
                                    .padding(.leading, 128)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Target Language:")
                                    .frame(width: 120, alignment: .trailing)
                                
                                FixedWidthPicker(
                                    selection: $targetLanguage,
                                    width: 250,
                                    label: { Text(targetLanguage == "none" ? "Same as Audio (No Translation)" : (whisperLanguages.first { $0.code == targetLanguage }?.name ?? "")) }
                                ) {
                                    Text("Same as Audio (No Translation)").tag("none")
                                    ForEach(whisperLanguages.filter { $0.code != "auto" }, id: \.code) { lang in
                                        Text(lang.name).tag(lang.code)
                                    }
                                }
                                .disabled(engineClient.transcribeFileIsProcessing)
                            }
                            
                            Text("(LLM Translation)")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                                .padding(.leading, 128)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Drop Zone
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isTargeted ? Color.sageGreen : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .background(isTargeted ? Color.sageGreen.opacity(0.1) : Color.clear)
                            .frame(height: 160)
                        
                        VStack(spacing: 12) {
                            if let url = engineClient.transcribeFileSelectedURL {
                                Image(systemName: "doc.audio.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.sageGreen)
                                Text(url.lastPathComponent)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal)
                                
                                Button("Clear") {
                                    engineClient.transcribeFileSelectedURL = nil
                                    engineClient.transcribeFileTranscribedText = ""
                                    engineClient.transcribeFileErrorMessage = nil
                                }
                                .buttonStyle(.link)
                                .foregroundColor(.red)
                                .disabled(engineClient.transcribeFileIsProcessing)
                            } else {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 40))
                                    .foregroundColor(.dictySecondary)
                                Text("Drag and drop an audio or video file here")
                                    .font(.headline)
                                    .foregroundColor(.dictySecondary)
                                Text("Supports .mp3, .wav, .m4a, .mp4, .mov, .mkv")
                                    .font(.caption)
                                    .foregroundColor(.dictySecondary)
                                
                                Button("Browse Files...") {
                                    let panel = NSOpenPanel()
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    panel.canCreateDirectories = false
                                    panel.allowedContentTypes = [.audio, .movie]
                                    if panel.runModal() == .OK, let url = panel.url {
                                        engineClient.transcribeFileSelectedURL = url
                                        engineClient.transcribeFileTranscribedText = ""
                                        engineClient.transcribeFileErrorMessage = nil
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                        if let provider = providers.first {
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                    DispatchQueue.main.async {
                                        self.engineClient.transcribeFileSelectedURL = url
                                        self.engineClient.transcribeFileTranscribedText = ""
                                        self.engineClient.transcribeFileErrorMessage = nil
                                    }
                                }
                            }
                            return true
                        }
                        return false
                    }
                    
                    if let error = engineClient.transcribeFileErrorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    if engineClient.transcribeFileIsProcessing {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Extracting and transcribing...")
                                .font(.headline)
                                .foregroundColor(.dictySecondary)
                            Text("This may take a few minutes depending on the file size.")
                                .font(.caption)
                                .foregroundColor(.dictySecondary)
                        }
                        .padding(40)
                    } else if !engineClient.transcribeFileTranscribedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Transcription Result")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(engineClient.transcribeFileTranscribedText, forType: .string)
                                }) {
                                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.sageGreen)
                            }
                            
                            TextEditor(text: $engineClient.transcribeFileTranscribedText)
                                .font(.system(.body, design: .rounded))
                                .frame(minHeight: 200, maxHeight: 400)
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                    } else if engineClient.transcribeFileSelectedURL != nil {
                        Button(action: {
                            Task {
                                await startTranscription()
                            }
                        }) {
                            Text("Transcribe File")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.sageGreen)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(40)
            }
        }
    }
    
    private func startTranscription() async {
        guard let url = engineClient.transcribeFileSelectedURL else { return }
        
        DispatchQueue.main.async {
            self.engineClient.transcribeFileIsProcessing = true
            self.engineClient.transcribeFileErrorMessage = nil
            self.engineClient.transcribeFileTranscribedText = ""
        }
        
        do {
            let actualLanguage = isEnglishOnly ? "en" : language
            let text = try await engineClient.transcribeLocalFile(url: url, targetModel: targetModel, language: actualLanguage, targetLanguage: targetLanguage)
            DispatchQueue.main.async {
                self.engineClient.transcribeFileTranscribedText = text
                self.engineClient.transcribeFileIsProcessing = false
                
                // Refresh history so the new transcription appears in the History tab
                self.engineClient.fetchHistory()
            }
        } catch {
            DispatchQueue.main.async {
                self.engineClient.transcribeFileErrorMessage = error.localizedDescription
                self.engineClient.transcribeFileIsProcessing = false
            }
        }
    }
}
