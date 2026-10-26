import SwiftUI
import AppKit

@MainActor
final class AppRuleSuggestionBannerWindow {
    static let shared = AppRuleSuggestionBannerWindow()
    private var panel: NSPanel?
    private var autoDismissTask: Task<Void, Never>?
    
    func show(suggestion: AppRuleSuggestion, engineClient: EngineClient) {
        autoDismissTask?.cancel()
        
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 50),
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
            self.panel = p
        }
        
        guard let p = panel else { return }
        
        let bannerView = AppRuleSuggestionBannerView(suggestion: suggestion, engineClient: engineClient)
        let hosting = NSHostingView(rootView: bannerView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = hosting
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let width: CGFloat = 500
            let height: CGFloat = 52
            let x = screenRect.midX - (width / 2)
            let y = screenRect.maxY - height - 16
            p.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        
        p.orderFrontRegardless()
        
        // Auto-dismiss after 15 seconds if untouched
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    self.hide()
                }
            }
        }
    }
    
    func hide() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel?.orderOut(nil)
    }
}

struct AppRuleSuggestionBannerView: View {
    let suggestion: AppRuleSuggestion
    @ObservedObject var engineClient: EngineClient
    
    private var appIcon: NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: suggestion.app_id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: suggestion.app_id).first {
            return app.icon
        }
        return nil
    }
    
    private var modeDisplayName: String {
        let modeOpt = availableAppRuleModes.first(where: { $0.id == suggestion.mode_id })
        return modeOpt?.name ?? suggestion.mode_id.capitalized
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // Question copy
            Text("Always use \(modeDisplayName) in \(suggestion.app_name)?")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            // Action buttons
            HStack(spacing: 6) {
                // Yes (Primary Accent Pill)
                Button(action: {
                    engineClient.acceptAppRuleSuggestion(suggestion)
                }) {
                    Text("Yes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.appAccent)
                        )
                }
                .buttonStyle(.plain)
                
                // Not now (Neutral secondary)
                Button(action: {
                    engineClient.dismissAppRuleSuggestion()
                }) {
                    Text("Not now")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                
                // Don't ask for this app
                Button(action: {
                    engineClient.suppressAppRuleSuggestion(appId: suggestion.app_id, displayName: suggestion.app_name)
                }) {
                    Text("Don't ask for this app")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.85)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        )
        .padding(4)
    }
}
