import SwiftUI
import AppKit

@MainActor
final class FloatingAudioHUDWindow {
    static let shared = FloatingAudioHUDWindow()
    private var panel: NSPanel?
    
    func show(ttsManager: TTSManager) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 56),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.isMovableByWindowBackground = true
            
            let hudView = FloatingAudioHUDView().environmentObject(ttsManager)
            let hosting = NSHostingView(rootView: hudView)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            p.contentView = hosting
            
            p.setFrameAutosaveName("DictyFloatingAudioHUDPosition")
            if p.frameAutosaveName.isEmpty || !UserDefaults.standard.bool(forKey: "AudioHUDPositionSaved") {
                if let screen = NSScreen.main {
                    let screenRect = screen.visibleFrame
                    let x = screenRect.midX - 225
                    let y = screenRect.minY + 80
                    p.setFrameOrigin(NSPoint(x: x, y: y))
                }
                UserDefaults.standard.set(true, forKey: "AudioHUDPositionSaved")
            }
            self.panel = p
        }
        
        panel?.orderFrontRegardless()
    }
    
    func hide() {
        panel?.orderOut(nil)
    }
}

struct FloatingAudioHUDView: View {
    @EnvironmentObject var tts: TTSManager
    @State private var isHovering: Bool = false
    @State private var isDraggingScrubber: Bool = false
    @State private var dragProgress: Double = 0.0
    
    var body: some View {
        HStack(spacing: 10) {
            // Audio wave animation or spinner
            if tts.isGenerating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.65)
                    .frame(width: 20, height: 20)
            } else {
                HStack(spacing: 2.5) {
                    ForEach(0..<4, id: \.self) { i in
                        PulsingAudioBar(isPaused: tts.isPaused, index: i)
                    }
                }
                .frame(width: 20, height: 16)
            }
            
            // Play / Pause / Resume Button
            if !tts.isGenerating {
                Button(action: {
                    tts.togglePlayPause()
                }) {
                    Image(systemName: tts.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tts.isPaused ? "Resume" : "Pause")
            }
            
            // Interactive Timeline Duration Bar
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let effectiveProgress = isDraggingScrubber ? dragProgress : tts.playbackProgress
                    let progressClamped = max(0.0, min(1.0, effectiveProgress))
                    let trackWidth = max(0.0, geo.size.width)
                    let thumbX = trackWidth * CGFloat(progressClamped)
                    
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 5)
                        
                        // Active progress fill
                        Capsule()
                            .fill(Color.sageGreen)
                            .frame(width: thumbX, height: 5)
                        
                        // Scrub Thumb Indicator
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, min(trackWidth - 10, thumbX - 5)))
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingScrubber = true
                                let fraction = max(0.0, min(1.0, Double(value.location.x / max(1.0, geo.size.width))))
                                dragProgress = fraction
                                tts.seek(toProgress: fraction)
                            }
                            .onEnded { value in
                                let fraction = max(0.0, min(1.0, Double(value.location.x / max(1.0, geo.size.width))))
                                tts.seek(toProgress: fraction)
                                isDraggingScrubber = false
                            }
                    )
                }
                .frame(height: 14)
                
                // Timestamps & Persona label
                HStack(spacing: 4) {
                    Text(formatTime(isDraggingScrubber ? dragProgress * tts.duration : tts.currentTime))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer(minLength: 4)
                    
                    Text(voiceDisplayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    Text(formatTime(tts.duration))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(minWidth: 160)
            
            // Speed Picker
            Menu {
                Button("0.75x") { tts.playbackSpeed = 0.75 }
                Button("1.0x (Normal)") { tts.playbackSpeed = 1.0 }
                Button("1.25x") { tts.playbackSpeed = 1.25 }
                Button("1.5x") { tts.playbackSpeed = 1.5 }
                Button("2.0x (Fast)") { tts.playbackSpeed = 2.0 }
            } label: {
                Text(String(format: "%.2gx", tts.playbackSpeed))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Close / Stop Button
            Button(action: {
                tts.stop()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 50)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.70)
            }
            .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .onHover { hovering in
            self.isHovering = hovering
        }
    }
    
    private var voiceDisplayName: String {
        if tts.isBlendingEnabled {
            let pName = tts.voice(for: tts.selectedVoice)?.name ?? "Voice A"
            let bName = tts.voice(for: tts.blendVoice)?.name ?? "Voice B"
            return "\(pName)+\(bName)"
        }
        if let v = tts.availableVoices.first(where: { $0.id == tts.selectedVoice }) {
            return v.name
        }
        return tts.selectedVoice.replacingOccurrences(of: "af_", with: "").replacingOccurrences(of: "bm_", with: "").capitalized
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let totalSecs = Int(seconds)
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct PulsingAudioBar: View {
    let isPaused: Bool
    let index: Int
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(isPaused ? 0.35 : 0.9))
            .frame(width: 3, height: isPaused ? 4 : (isAnimating ? 14 : 4))
            .animation(
                isPaused ? .default : Animation.easeInOut(duration: 0.35)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.08),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
