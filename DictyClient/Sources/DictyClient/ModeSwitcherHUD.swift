import SwiftUI
import AppKit

// MARK: - Custom Floating HUD Panel that accepts key events directly
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    var onKeyDownHandler: ((NSEvent) -> Bool)?
    
    override func keyDown(with event: NSEvent) {
        if let handled = onKeyDownHandler?(event), handled {
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Mode Switcher HUD Window Manager
@MainActor
final class ModeSwitcherHUDManager: ObservableObject {
    static let shared = ModeSwitcherHUDManager()
    
    private var panel: KeyablePanel?
    private var globalEventMonitor: Any?
    
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false
    
    func toggle(engineClient: EngineClient) {
        if isVisible {
            hide()
        } else {
            show(engineClient: engineClient)
        }
    }
    
    func show(engineClient: EngineClient) {
        let profiles = ProfileManager.shared.profiles
        if let currentIdx = profiles.firstIndex(where: { $0.id == ProfileManager.shared.activeProfileId }) {
            self.selectedIndex = currentIdx
        } else {
            self.selectedIndex = 0
        }
        
        if panel == nil {
            let panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            
            let contentView = ModeSwitcherHUDView(
                hudManager: self,
                onClose: { [weak self] in
                    self?.hide()
                }
            )
            .environmentObject(engineClient)
            
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            
            panel.contentView = hostingView
            self.panel = panel
        }
        
        panel?.onKeyDownHandler = { [weak self] event in
            guard let self = self else { return false }
            return self.handleKeyDown(keyCode: event.keyCode, engineClient: engineClient)
        }
        
        // Re-center on active screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 170
            let y = screenRect.midY - 130
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel?.center()
        }
        
        self.isVisible = true
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        setupGlobalMonitor(engineClient: engineClient)
    }
    
    func hide() {
        self.isVisible = false
        panel?.orderOut(nil)
        removeGlobalMonitor()
    }
    
    func selectAndClose(engineClient: EngineClient) {
        guard isVisible else { return }
        let profiles = ProfileManager.shared.profiles
        let count = min(profiles.count, 9)
        if count > 0 && selectedIndex >= 0 && selectedIndex < count {
            ProfileManager.shared.switchProfile(to: profiles[selectedIndex].id, engine: engineClient)
        }
        hide()
    }
    
    private func removeGlobalMonitor() {
        if let g = globalEventMonitor {
            NSEvent.removeMonitor(g)
            globalEventMonitor = nil
        }
    }
    
    func handleKeyDown(keyCode: UInt16, engineClient: EngineClient) -> Bool {
        guard isVisible else { return false }
        let profiles = ProfileManager.shared.profiles
        let count = min(profiles.count, 9)
        guard count > 0 else { return false }
        
        switch keyCode {
        case 53: // Escape
            hide()
            return true
            
        case 126: // Up Arrow
            selectedIndex = (selectedIndex - 1 + count) % count
            return true
            
        case 125: // Down Arrow
            selectedIndex = (selectedIndex + 1) % count
            return true
            
        case 36, 49: // Return or Space
            if selectedIndex >= 0 && selectedIndex < count {
                ProfileManager.shared.switchProfile(to: profiles[selectedIndex].id, engine: engineClient)
            }
            hide()
            return true
            
        case 18: // '1'
            selectIndex(0, engineClient: engineClient)
            return true
        case 19: // '2'
            selectIndex(1, engineClient: engineClient)
            return true
        case 20: // '3'
            selectIndex(2, engineClient: engineClient)
            return true
        case 21: // '4'
            selectIndex(3, engineClient: engineClient)
            return true
        case 23: // '5'
            selectIndex(4, engineClient: engineClient)
            return true
        case 22: // '6'
            selectIndex(5, engineClient: engineClient)
            return true
        case 26: // '7'
            selectIndex(6, engineClient: engineClient)
            return true
        case 28: // '8'
            selectIndex(7, engineClient: engineClient)
            return true
        case 25: // '9'
            selectIndex(8, engineClient: engineClient)
            return true
            
        default:
            return false
        }
    }
    
    private func selectIndex(_ index: Int, engineClient: EngineClient) {
        let profiles = ProfileManager.shared.profiles
        if index < profiles.count {
            ProfileManager.shared.switchProfile(to: profiles[index].id, engine: engineClient)
            hide()
        }
    }
    
    private func setupGlobalMonitor(engineClient: EngineClient) {
        removeGlobalMonitor()
        
        globalEventMonitor = EventMonitorRegistrar.registerGlobal(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            Task { @MainActor [weak self] in
                guard let self = self, self.isVisible else { return }
                _ = self.handleKeyDown(keyCode: keyCode, engineClient: engineClient)
            }
        }
    }
}

// MARK: - Mode Switcher HUD View
struct ModeSwitcherHUDView: View {
    @ObservedObject var hudManager: ModeSwitcherHUDManager
    @EnvironmentObject var engineClient: EngineClient
    @ObservedObject var profileManager = ProfileManager.shared
    
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Modes List
            VStack(spacing: 6) {
                ForEach(Array(profileManager.profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                    let isActive = profile.id == profileManager.activeProfileId
                    let isSelected = (hudManager.selectedIndex == index)
                    
                    Button(action: {
                        hudManager.selectedIndex = index
                        profileManager.switchProfile(to: profile.id, engine: engineClient)
                        onClose()
                    }) {
                        HStack(spacing: 12) {
                            // Mode Icon
                            Image(systemName: profile.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isActive ? .appAccent : .secondary)
                                .frame(width: 20)
                            
                            // Mode Name
                            Text(profile.name)
                                .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .foregroundColor(.primary)
                            
                            if DictyAudioRecorder.isSystemAudioMode(profile.activeMode) && !CGPreflightScreenCaptureAccess() {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.warmAmber)
                                    .help("Screen & System Audio Recording permission required")
                            }
                            
                            Spacer()
                            
                            // Right: Checkmark or Number Badge
                            if isActive {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.appAccent)
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 18, height: 18)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            hudManager.selectedIndex = index
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Legend Bar
            HStack(spacing: 10) {

                
                Spacer()
                
                // Keyboard Shortcuts Legend
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Text("↑")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(3)
                        Text("↓")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(3)
                    }
                    
                    HStack(spacing: 4) {
                        Text("Select")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("↩")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(3)
                    }
                    
                    HStack(spacing: 4) {
                        Text("Back")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("esc")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(3)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
}
