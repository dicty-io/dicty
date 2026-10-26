import SwiftUI
import AppKit
import Network

final class VolumeReceiver: ObservableObject, @unchecked Sendable {
    @Published var currentVolume: Float = 0.0
    private var listener: NWListener?
    
    func start() {
        do {
            let parameters = NWParameters.udp
            listener = try NWListener(using: parameters, on: 55555)
            listener?.newConnectionHandler = { connection in
                connection.start(queue: .main)
                self.receive(on: connection)
            }
            listener?.start(queue: .main)
        } catch {
            print("Failed to start UDP listener: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, let str = String(data: data, encoding: .utf8), let vol = Float(str) {
                DispatchQueue.main.async {
                    self.currentVolume = vol
                }
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }
}

@MainActor
class TranscriptionStreamReceiver: ObservableObject {
    @Published var partialText: String = ""
    private var webSocketTask: URLSessionWebSocketTask?
    private var hasRetried = false
    private var isStopping = false

    func start() {
        stop()
        isStopping = false
        hasRetried = false
        connect()
    }

    private func connect() {
        let request = EngineEndpoint.shared.webSocketRequest("/ws/transcribe/stream")
        let task = EngineEndpoint.shared.webSocketSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        receiveMessage(for: task)
    }

    func stop() {
        isStopping = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        partialText = ""
    }

    private func receiveMessage(for task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self, let task, !self.isStopping, self.webSocketTask === task else { return }
                switch result {
                case .failure(let error):
                    // A restarted engine closes the socket with 4401. Re-read the
                    // token file and reconnect exactly once.
                    if !self.hasRetried {
                        self.hasRetried = true
                        EngineEndpoint.shared.reloadTokenFromDisk()
                        self.connect()
                    } else {
                        print("WebSocket error: \(error)")
                    }
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let status = json["status"] as? String,
                           status == "partial",
                           let newText = json["text"] as? String {
                            self.partialText = newText
                        }
                    default: break
                    }
                    self.receiveMessage(for: task)
                }
            }
        }
    }
}

enum OverlayDockPosition: String, CaseIterable {
    case freeform   // User-dragged position
    case top        // Top center of screen
    case bottom     // Bottom center of screen
    case left       // Left center of screen
    case right      // Right center of screen
    
    var isVertical: Bool {
        return self == .left || self == .right
    }
}


// MARK: - Drop Zone Indicator Window
// A transparent overlay window that shows a semi-transparent white oval at a screen edge
// with a centered waveform badge when the user drags the recording overlay, WhisperFlow-style.
@MainActor
class DockDropZoneWindow {
    let position: OverlayDockPosition
    private let window: NSWindow
    private let ovalView: NSView
    private let iconContainer: NSView
    private var isHighlighted = false
    
    var zoneRect: NSRect { window.frame }
    
    init(position: OverlayDockPosition) {
        self.position = position
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let oval = NSView()
        oval.wantsLayer = true
        oval.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        oval.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        oval.layer?.borderWidth = 1.5
        
        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        iconBg.layer?.cornerRadius = 14
        iconBg.layer?.masksToBounds = true
        
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let img = DictyResources.image(named: "dicty_tray_icon", extension: "png") {
            let template = img.copy() as! NSImage
            template.size = NSSize(width: 16, height: 16)
            template.isTemplate = true
            iconView.image = template
            iconView.contentTintColor = .white
        }
        iconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        iconBg.addSubview(iconView)
        
        oval.addSubview(iconBg)
        window.contentView = oval
        
        self.window = window
        self.ovalView = oval
        self.iconContainer = iconBg
    }
    
    func layoutForScreen(_ screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let zoneSize: NSSize
        var origin: NSPoint
        let cornerRadius: CGFloat
        
        switch position {
        case .top:
            zoneSize = NSSize(width: 130, height: 70)
            origin = NSPoint(
                x: visibleFrame.midX - zoneSize.width / 2,
                y: visibleFrame.maxY - zoneSize.height - 12
            )
            cornerRadius = 35
        case .bottom:
            zoneSize = NSSize(width: 130, height: 70)
            origin = NSPoint(
                x: visibleFrame.midX - zoneSize.width / 2,
                y: visibleFrame.minY + 12
            )
            cornerRadius = 35
        case .left:
            zoneSize = NSSize(width: 70, height: 130)
            origin = NSPoint(
                x: visibleFrame.minX + 12,
                y: visibleFrame.midY - zoneSize.height / 2
            )
            cornerRadius = 35
        case .right:
            zoneSize = NSSize(width: 70, height: 130)
            origin = NSPoint(
                x: visibleFrame.maxX - zoneSize.width - 12,
                y: visibleFrame.midY - zoneSize.height / 2
            )
            cornerRadius = 35
        case .freeform:
            return
        }
        
        window.setFrame(NSRect(origin: origin, size: zoneSize), display: true)
        ovalView.frame = NSRect(origin: .zero, size: zoneSize)
        ovalView.layer?.cornerRadius = cornerRadius
        iconContainer.frame = NSRect(
            x: (zoneSize.width - 28) / 2,
            y: (zoneSize.height - 28) / 2,
            width: 28,
            height: 28
        )
    }
    
    func show() {
        window.alphaValue = 0.0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.window.orderOut(nil)
            }
        })
    }
    
    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            if highlighted {
                ovalView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.45).cgColor
                ovalView.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
                ovalView.layer?.borderWidth = 2.5
                iconContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
            } else {
                ovalView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
                ovalView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
                ovalView.layer?.borderWidth = 1.5
                iconContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
            }
        }
    }
}

// MARK: - Draggable Overlay Panel
// Custom NSPanel that intercepts mouse drag events directly via AppKit.
// This guarantees smooth, continuous window tracking across all screens,
// eliminating SwiftUI DragGesture hit-testing and cancellation issues on small sticks.
@MainActor
class DraggableOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var isDraggingOverlay = false
    
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = self.frame.origin
            isDraggingOverlay = false
            super.sendEvent(event)
            
        case .leftMouseDragged:
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - dragStartMouseLocation.x
            let dy = currentMouse.y - dragStartMouseLocation.y
            let dist = hypot(dx, dy)
            
            if !isDraggingOverlay && dist >= 3 {
                isDraggingOverlay = true
                OverlayWindowManager.shared.beginDrag(startMouse: dragStartMouseLocation, startOrigin: dragStartWindowOrigin)
            }
            
            if isDraggingOverlay {
                OverlayWindowManager.shared.updateDrag(currentMouse: currentMouse)
                return
            }
            super.sendEvent(event)
            
        case .leftMouseUp:
            if isDraggingOverlay {
                isDraggingOverlay = false
                OverlayWindowManager.shared.endDrag()
                return
            }
            super.sendEvent(event)
            
        default:
            super.sendEvent(event)
        }
    }
}

// MARK: - Overlay Window Manager
@MainActor
class OverlayWindowManager: ObservableObject {
    static let shared = OverlayWindowManager()
    private var panel: DraggableOverlayPanel?
    
    @Published var dockPosition: OverlayDockPosition = {
        if let raw = UserDefaults.standard.string(forKey: "overlayDockPosition"),
           let pos = OverlayDockPosition(rawValue: raw) {
            return pos
        }
        return .bottom
    }() {
        didSet {
            UserDefaults.standard.set(dockPosition.rawValue, forKey: "overlayDockPosition")
        }
    }
    
    @Published var isExpanded: Bool = {
        UserDefaults.standard.bool(forKey: "overlayIsExpandedV2")
    }() {
        didSet {
            UserDefaults.standard.set(isExpanded, forKey: "overlayIsExpandedV2")
            snapToPosition(dockPosition, animated: true)
        }
    }
    
    // Drag-to-dock state
    private var dropZones: [DockDropZoneWindow] = []
    private(set) var isDragging = false
    private var activeDockTarget: OverlayDockPosition?
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var lastScreen: NSScreen?
    
    var isVisible: Bool {
        return panel?.isVisible ?? false
    }
    
    var currentWindowSize: NSSize {
        standardWindowSize(for: dockPosition, expanded: isExpanded)
    }
    
    func standardWindowSize(for position: OverlayDockPosition, expanded: Bool? = nil) -> NSSize {
        let isExp = expanded ?? isExpanded
        if isExp {
            return NSSize(width: 320, height: 140)
        }
        if position.isVertical {
            return NSSize(width: 60, height: 180)
        } else {
            return NSSize(width: 280, height: 60)
        }
    }
    
    func targetOriginFor(position: OverlayDockPosition, size: NSSize, screen: NSScreen) -> NSPoint {
        let visibleFrame = screen.visibleFrame
        switch position {
        case .left:
            return NSPoint(
                x: visibleFrame.minX,
                y: visibleFrame.midY - size.height / 2
            )
        case .right:
            return NSPoint(
                x: visibleFrame.maxX - size.width,
                y: visibleFrame.midY - size.height / 2
            )
        case .top:
            return NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height
            )
        case .bottom:
            return NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY
            )
        case .freeform:
            if let x = UserDefaults.standard.object(forKey: "overlayFreeformOriginX") as? CGFloat,
               let y = UserDefaults.standard.object(forKey: "overlayFreeformOriginY") as? CGFloat {
                return NSPoint(x: x, y: y)
            }
            return NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY
            )
        }
    }
    
    func show(engineClient: EngineClient) {
        if panel == nil {
            let initialSize = standardWindowSize(for: dockPosition, expanded: isExpanded)
            let panel = DraggableOverlayPanel(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            
            let overlayView = RecordingOverlayView()
                .environmentObject(engineClient)
            let hostingView = NSHostingView(rootView: overlayView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            
            panel.contentView = hostingView
            self.panel = panel
            
            // Clean up any stale window-autosave keys from older builds to prevent clipping
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame DictyRecordingOverlayPositionV3")
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame DictyRecordingOverlayPositionV2")
            
            dropZones = [.top, .bottom, .left, .right].map { DockDropZoneWindow(position: $0) }
            
            snapToPosition(dockPosition, animated: false)
        }
        
        updateVisibility(engineClient: engineClient)
    }
    
    func updateVisibility(engineClient: EngineClient) {
        guard let panel = panel else { return }
        if isExpanded {
            // Normal scale window is ONLY visible while recording or processing
            if engineClient.isRecording || engineClient.isProcessing {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        } else {
            // Tiny window mode companion stick is always visible
            panel.orderFrontRegardless()
        }
    }
    
    func hide() {
        panel?.orderOut(nil)
        hideDropZones()
    }
    
    var panelOrigin: NSPoint {
        panel?.frame.origin ?? .zero
    }
    
    func setPanelOrigin(_ origin: NSPoint) {
        panel?.setFrameOrigin(origin)
    }
    
    // MARK: - Drag-to-Dock System
    
    func beginDrag(startMouse: NSPoint, startOrigin: NSPoint) {
        guard panel != nil else { return }
        isDragging = true
        dragStartMouseLocation = startMouse
        dragStartWindowOrigin = startOrigin
        activeDockTarget = nil
        if !isExpanded {
            showDropZones()
        }
    }
    
    func updateDrag(currentMouse: NSPoint) {
        guard let panel = panel, isDragging else { return }
        
        let dx = currentMouse.x - dragStartMouseLocation.x
        let dy = currentMouse.y - dragStartMouseLocation.y
        let rawOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
        
        if isExpanded {
            // Normal scale window moves freely with NO drop zones and NO border attachment
            panel.setFrameOrigin(rawOrigin)
            return
        }
        
        let rawCenter = NSPoint(x: rawOrigin.x + panel.frame.width / 2, y: rawOrigin.y + panel.frame.height / 2)
        
        // Active screen determination
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(currentMouse) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(rawCenter) })
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
            
        if activeScreen != lastScreen {
            lastScreen = activeScreen
            for zone in dropZones {
                zone.layoutForScreen(activeScreen)
            }
        }
        
        // Check proximity to drop zones
        var matchingZone: OverlayDockPosition?
        var closestDist: CGFloat = .infinity
        let snapDistance: CGFloat = 160
        
        for zone in dropZones {
            let zoneCenter = NSPoint(x: zone.zoneRect.midX, y: zone.zoneRect.midY)
            let distMouse = hypot(currentMouse.x - zoneCenter.x, currentMouse.y - zoneCenter.y)
            let distPanel = hypot(rawCenter.x - zoneCenter.x, rawCenter.y - zoneCenter.y)
            let isInside = zone.zoneRect.insetBy(dx: -35, dy: -35).contains(currentMouse) ||
                           zone.zoneRect.insetBy(dx: -35, dy: -35).contains(rawCenter)
            let bestDist = min(distMouse, distPanel)
            
            if (isInside || bestDist < snapDistance) && bestDist < closestDist {
                closestDist = bestDist
                matchingZone = zone.position
            }
        }
        
        activeDockTarget = matchingZone
        
        // Highlight active zone
        for zone in dropZones {
            zone.setHighlighted(zone.position == matchingZone)
        }
        
        // When moving to the oval region, bring the window to the target static fixed position
        if let target = matchingZone {
            let targetSize = standardWindowSize(for: target, expanded: isExpanded)
            let targetOrigin = targetOriginFor(position: target, size: targetSize, screen: activeScreen)
            panel.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
            if dockPosition != target {
                dockPosition = target
            }
        } else {
            let targetSize = standardWindowSize(for: .freeform, expanded: isExpanded)
            panel.setFrame(NSRect(origin: rawOrigin, size: targetSize), display: true)
            if dockPosition != .freeform {
                dockPosition = .freeform
            }
        }
    }
    
    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        hideDropZones()
        
        if isExpanded {
            if let panel = panel {
                dockPosition = .freeform
                UserDefaults.standard.set(OverlayDockPosition.freeform.rawValue, forKey: "overlayDockPosition")
                UserDefaults.standard.set(panel.frame.origin.x, forKey: "overlayFreeformOriginX")
                UserDefaults.standard.set(panel.frame.origin.y, forKey: "overlayFreeformOriginY")
            }
            return
        }
        
        let target = activeDockTarget ?? currentTargetDropPosition()
        activeDockTarget = nil
        
        if target != .freeform {
            snapToPosition(target, animated: true)
        } else if let panel = panel {
            dockPosition = .freeform
            UserDefaults.standard.set(OverlayDockPosition.freeform.rawValue, forKey: "overlayDockPosition")
            UserDefaults.standard.set(panel.frame.origin.x, forKey: "overlayFreeformOriginX")
            UserDefaults.standard.set(panel.frame.origin.y, forKey: "overlayFreeformOriginY")
        }
    }
    
    func currentTargetDropPosition() -> OverlayDockPosition {
        guard let panel = panel else { return .freeform }
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let mouseLocation = NSEvent.mouseLocation
        
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
            
        let visibleFrame = screen.visibleFrame
        
        var closestPosition: OverlayDockPosition?
        var closestDistance: CGFloat = .infinity
        let snapThreshold: CGFloat = 160
        
        for zone in dropZones {
            let zoneCenter = NSPoint(x: zone.zoneRect.midX, y: zone.zoneRect.midY)
            let dxP = panelCenter.x - zoneCenter.x
            let dyP = panelCenter.y - zoneCenter.y
            let distP = sqrt(dxP * dxP + dyP * dyP)
            
            let dxM = mouseLocation.x - zoneCenter.x
            let dyM = mouseLocation.y - zoneCenter.y
            let distM = sqrt(dxM * dxM + dyM * dyM)
            
            let isPanelInside = zone.zoneRect.insetBy(dx: -40, dy: -40).contains(panelCenter)
            let isMouseInside = zone.zoneRect.insetBy(dx: -40, dy: -40).contains(mouseLocation)
            
            let bestDist = min(distP, distM)
            if (bestDist < snapThreshold || isPanelInside || isMouseInside) && bestDist < closestDistance {
                closestDistance = bestDist
                closestPosition = zone.position
            }
        }
        
        if let pos = closestPosition {
            return pos
        }
        
        // Edge fallback (if mouse or panel is close to any bezel)
        let edgeMargin: CGFloat = 70
        if mouseLocation.x < visibleFrame.minX + edgeMargin || panelCenter.x < visibleFrame.minX + edgeMargin {
            return .left
        }
        if mouseLocation.x > visibleFrame.maxX - edgeMargin || panelCenter.x > visibleFrame.maxX - edgeMargin {
            return .right
        }
        if mouseLocation.y > visibleFrame.maxY - edgeMargin || panelCenter.y > visibleFrame.maxY - edgeMargin {
            return .top
        }
        if mouseLocation.y < visibleFrame.minY + edgeMargin || panelCenter.y < visibleFrame.minY + edgeMargin {
            return .bottom
        }
        
        return .freeform
    }
    
    private func showDropZones() {
        guard let screen = panel?.screen ?? NSScreen.main else { return }
        lastScreen = screen
        for zone in dropZones {
            zone.layoutForScreen(screen)
            zone.show()
        }
    }
    
    private func hideDropZones() {
        for zone in dropZones {
            zone.setHighlighted(false)
            zone.hide()
        }
    }
    
    func snapToPosition(_ position: OverlayDockPosition, animated: Bool) {
        dockPosition = position
        
        guard let panel = panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        
        let targetSize = standardWindowSize(for: position, expanded: isExpanded)
        let targetOrigin = targetOriginFor(position: position, size: targetSize, screen: screen)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)
        
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var windowManager = OverlayWindowManager.shared
    @EnvironmentObject var engineClient: EngineClient
    @StateObject private var volumeReceiver = VolumeReceiver()
    @StateObject private var streamReceiver = TranscriptionStreamReceiver()
    
    @AppStorage("showModeLabel") private var showModeLabel: Bool = true
    @AppStorage("colorHex_dictation") private var colorHexDictation: String = "78B18D"
    @AppStorage("colorHex_librarian") private var colorHexLibrarian: String = "7E8CE0"
    @AppStorage("colorHex_meeting") private var colorHexMeeting: String = "EAA368"
    @AppStorage("colorHex_focused") private var colorHexFocused: String = "EB7575"
    
    @State private var isHovering = false
    
    var dockPosition: OverlayDockPosition {
        windowManager.dockPosition
    }
    
    var isExpanded: Bool {
        get { windowManager.isExpanded }
        nonmutating set { windowManager.isExpanded = newValue }
    }
    
    var contentAlignment: Alignment {
        if isExpanded {
            return .center
        }
        switch dockPosition {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        case .freeform: return .center
        }
    }
    
    var body: some View {
        ZStack(alignment: contentAlignment) {
            if isExpanded {
                expandedView
            } else if dockPosition.isVertical {
                verticalMiniView
                    .onHover { hover in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isHovering = hover
                        }
                    }
            } else {
                horizontalMiniView
                    .onHover { hover in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isHovering = hover
                        }
                    }
            }
        }
        .frame(
            width: windowManager.currentWindowSize.width,
            height: windowManager.currentWindowSize.height,
            alignment: contentAlignment
        )
        .onAppear {
            if colorHexDictation.uppercased() == "4CAF50" { colorHexDictation = "78B18D" }
            if colorHexLibrarian.uppercased() == "5856D6" { colorHexLibrarian = "7E8CE0" }
            if colorHexMeeting.uppercased() == "FF9500" { colorHexMeeting = "EAA368" }
            if colorHexFocused.uppercased() == "FF3B30" { colorHexFocused = "EB7575" }
            volumeReceiver.start()
            streamReceiver.start()
            windowManager.updateVisibility(engineClient: engineClient)
        }
        .onDisappear {
            volumeReceiver.stop()
            streamReceiver.stop()
        }
        .onChange(of: engineClient.isRecording) { _, newValue in
            if newValue {
                streamReceiver.partialText = ""
            }
            windowManager.updateVisibility(engineClient: engineClient)
        }
        .onChange(of: engineClient.isProcessing) { _, _ in
            windowManager.updateVisibility(engineClient: engineClient)
        }
        .onChange(of: windowManager.isExpanded) { _, _ in
            windowManager.updateVisibility(engineClient: engineClient)
        }
    }
    
    private func modeLabel(_ id: String, _ title: String) -> String {
        return engineClient.activeMode == id ? "✓ " + title : "    " + title
    }
    
    private var modeIndicatorLabel: some View {
        let letter: String
        let color: Color
        switch engineClient.activeMode {
        case "dictation":
            letter = "D"
            color = Color(hex: colorHexDictation)
        case "librarian":
            letter = "L"
            color = Color(hex: colorHexLibrarian)
        case "meeting":
            letter = "M"
            color = Color(hex: colorHexMeeting)
        case "focused_meeting":
            letter = "F"
            color = Color(hex: colorHexFocused)
        default:
            letter = "D"
            color = Color.gray
        }
        
        return Text(letter)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 14, height: 14)
            .background(color)
            .clipShape(Circle())
            .shadow(color: color.opacity(0.4), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Background Styling
    
    private var capsuleBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(Color(red: 0.08, green: 0.1, blue: 0.12).opacity(0.78))
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.1, blue: 0.12).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    // MARK: - Vertical Mini View (WhisperFlow Left / Right Dock - 3x Narrower)
    
    private var verticalMiniView: some View {
        Group {
            if engineClient.isProcessing {
                VStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.55)
                        .frame(width: 13, height: 13)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 3.5)
                .background(capsuleBackground)
            } else if engineClient.isRecording {
                // WhisperFlow-style slender vertical recording capsule (3x narrower)
                VStack(spacing: 6) {
                    // Cancel / Discard button (X)
                    Button(action: {
                        engineClient.cancelRecording()
                    }) {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 13, height: 13)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Recording (Discard)")
                    
                    // Slender vertical waveform visualizer
                    VStack(spacing: 2) {
                        let vol = CGFloat(volumeReceiver.currentVolume * 600.0)
                        let multipliers: [CGFloat] = [0.4, 0.75, 1.0, 0.75, 0.4]
                        ForEach(0..<5, id: \.self) { i in
                            let w = max(3.0, min(10.0, 3.0 + vol * multipliers[i]))
                            RoundedRectangle(cornerRadius: 1.0)
                                .fill(Color.white)
                                .frame(width: w, height: 2)
                                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.7), value: w)
                        }
                    }
                    .frame(width: 10, height: 20)
                    
                    if engineClient.isPaused {
                        Circle()
                            .fill(Color.warmAmber)
                            .frame(width: 4, height: 4)
                    }
                    if engineClient.isMicMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color.warmAmber)
                    }
                    
                    // Finish button (✓)
                    Button(action: {
                        engineClient.toggleRecording()
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 13, height: 13)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Finish & Transcribe")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 3)
                .background(capsuleBackground)
            } else {
                // WhisperFlow idle vertical stick ("палочка")
                VStack(spacing: 5) {
                    if isHovering {
                        // Quick record button
                        Button(action: {
                            engineClient.toggleRecording()
                        }) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 13, height: 13)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Start Recording")
                        
                        // Mode Indicator
                        modeIndicatorLabel
                        
                        // Expand
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded = true
                            }
                        }) {
                            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Expand")
                    } else {
                        // Minimalist stick
                        Capsule()
                            .fill(Color.white.opacity(0.65))
                            .frame(width: 3.5, height: 32)
                    }
                }
                .padding(.vertical, isHovering ? 6 : 5)
                .padding(.horizontal, isHovering ? 4 : 3.5)
                .background(capsuleBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isHovering {
                        engineClient.toggleRecording()
                    }
                }
            }
        }
    }
    
    // MARK: - Horizontal Mini View (Top / Bottom / Freeform Dock - Slender)
    
    private var horizontalMiniView: some View {
        Group {
            if engineClient.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.55)
                        .frame(width: 13, height: 13)
                    Text(engineClient.processingStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(capsuleBackground)
            } else if engineClient.isRecording {
                // WhisperFlow-style slender horizontal recording capsule (3x narrower)
                HStack(spacing: 6) {
                    // Cancel / Discard button (X)
                    Button(action: {
                        engineClient.cancelRecording()
                    }) {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 13, height: 13)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Recording (Discard)")
                    
                    if engineClient.isPaused {
                        HStack(spacing: 3) {
                            Circle().fill(Color.warmAmber).frame(width: 4, height: 4)
                            Text("PAUSED")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    } else {
                        // Waveform equalizer bars
                        HStack(spacing: 2) {
                            let vol = CGFloat(volumeReceiver.currentVolume * 600.0)
                            let multipliers: [CGFloat] = [0.4, 0.75, 1.0, 0.75, 0.4]
                            ForEach(0..<5, id: \.self) { i in
                                let h = max(3.0, min(10.0, 3.0 + vol * multipliers[i]))
                                RoundedRectangle(cornerRadius: 1.0)
                                    .fill(Color.white)
                                    .frame(width: 2, height: h)
                                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.7), value: h)
                            }
                        }
                        .frame(height: 10)
                    }
                    
                    if engineClient.isMicMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color.warmAmber)
                    }
                    if engineClient.isIncognitoMode {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    AppModeChipView(engineClient: engineClient)
                    
                    // Finish button (✓)
                    Button(action: {
                        engineClient.toggleRecording()
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 13, height: 13)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Finish & Transcribe")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(capsuleBackground)
            } else {
                // WhisperFlow idle horizontal stick ("палочка")
                HStack(spacing: 8) {
                    if isHovering {
                        // Change Mode Menu
                        Menu {
                            Button(modeLabel("dictation", "Dictation")) { engineClient.activeMode = "dictation" }
                            Button(modeLabel("librarian", "Librarian (Alpha)")) { engineClient.activeMode = "librarian" }
                            Button(modeLabel("meeting", "Meeting (Alpha)")) { engineClient.activeMode = "meeting" }
                            Button(modeLabel("focused_meeting", "Focused Meeting (Alpha)")) { engineClient.activeMode = "focused_meeting" }
                        } label: {
                            if showModeLabel {
                                modeIndicatorLabel
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Change Mode")
                        
                        // Start Recording
                        Button(action: {
                            engineClient.toggleRecording()
                        }) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 13, height: 13)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Start Recording")
                        
                        // Expand
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded = true
                            }
                        }) {
                            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Expand")
                    } else {
                        // Minimalist stick
                        Capsule()
                            .fill(Color.white.opacity(0.65))
                            .frame(width: 32, height: 3.5)
                    }
                }
                .padding(.horizontal, isHovering ? 8 : 5)
                .padding(.vertical, isHovering ? 4 : 3.5)
                .background(capsuleBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isHovering {
                        engineClient.toggleRecording()
                    }
                }
            }
        }
    }
    
    private var expandedView: some View {
        VStack(spacing: 10) {
                // Animated Pulsing Equalizer / Paused Banner / Processing
                if engineClient.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                        Text(engineClient.processingStatusMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 32)
                } else if engineClient.isRecording {
                    if engineClient.isPaused {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.warmAmber)
                                .frame(width: 8, height: 8)
                            Text("Recording Paused")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
                            Text("— Press \(engineClient.pauseShortcutDisplay) to resume")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 32)
                    } else if engineClient.isMicMuted {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.slash.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.warmAmber)
                            Text("Microphone Muted")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
                            if DictyAudioRecorder.isSystemAudioMode(engineClient.activeMode) {
                                Text("• Recording System Audio Only")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 32)
                    } else {
                        HStack(spacing: 1.5) {
                            let vol = CGFloat(volumeReceiver.currentVolume * 300.0)
                            let totalBars = 55
                            
                            ForEach(0..<totalBars, id: \.self) { i in
                                let x = CGFloat(i) / CGFloat(totalBars - 1)
                                
                                // A dome shape so the edges taper off cleanly
                                let dome = sin(x * .pi)
                                
                                // A sum of sine waves to create a static, organic, jagged waveform envelope
                                let jagged = 0.5 + 0.3 * sin(x * 45) + 0.2 * cos(x * 85) + 0.1 * sin(x * 130)
                                
                                let multiplier = dome * jagged * 1.5
                                let height = max(3.0, vol * multiplier)
                                
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white)
                                    .frame(width: 2, height: min(height, 28))
                                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.7), value: height)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 32)
                        
                        if !streamReceiver.partialText.isEmpty {
                            Text(streamReceiver.partialText)
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .transition(.opacity)
                        }
                    }
                } else {
                    // Placeholder when not recording
                    Text("Ready to dictate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 32)
                }
                
                // Target App & Mode Chip
                AppModeChipView(engineClient: engineClient)
                
                // Action Buttons
                if !engineClient.isProcessing {
                    HStack(spacing: 7) {
                        if engineClient.isRecording {
                            Button(action: {
                                engineClient.togglePauseRecording()
                            }) {
                                HStack(spacing: 3) {
                                    Text(engineClient.isPaused ? "Resume" : "Pause")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text(engineClient.pauseShortcutDisplay)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 3.5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(3)
                                }
                                .foregroundColor(engineClient.isPaused ? Color.warmAmber : .white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .help(engineClient.isPaused ? "Resume Recording (\(engineClient.pauseShortcutDisplay))" : "Pause Recording (\(engineClient.pauseShortcutDisplay))")
                        }
                        
                        if engineClient.isRecording {
                            Button(action: {
                                engineClient.toggleMicMute()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: engineClient.isMicMuted ? "mic.slash.fill" : "mic.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(engineClient.isMicMuted ? "Unmute" : "Mute")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundColor(engineClient.isMicMuted ? Color.warmAmber : .white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .help(engineClient.isMicMuted ? "Unmute Microphone" : "Mute Microphone (Record system audio only)")
                        }
                        
                        Button(action: {
                            engineClient.toggleRecording()
                        }) {
                            HStack(spacing: 3) {
                                Text(engineClient.isRecording ? "Stop" : "Start")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(engineClient.recordShortcutDisplay)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(3)
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .help(engineClient.isRecording ? "Stop & Transcribe (\(engineClient.recordShortcutDisplay))" : "Start Recording (\(engineClient.recordShortcutDisplay))")
                        
                        if engineClient.isRecording {
                            Button(action: {
                                engineClient.cancelRecording()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Cancel")
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .help("Cancel Recording (Discard)")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
        .frame(width: 290)
        .overlay(alignment: .topTrailing) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isExpanded = false }
            }) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("Collapse")
            .onHover { isHovering in
                if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 5) {
                if showModeLabel {
                    modeIndicatorLabel
                        .allowsHitTesting(false)
                }
                
                if engineClient.isMicMuted {
                    Button(action: {
                        engineClient.toggleMicMute()
                    }) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.warmAmber)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Microphone Muted: Recording system audio only. Click to unmute")
                    .transition(.opacity.combined(with: .scale))
                }
                
                if engineClient.isIncognitoMode {
                    Button(action: {
                        engineClient.toggleIncognitoMode()
                    }) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Incognito Mode: Audio and dictation are not saved. Click to toggle")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(8)
        }
        .background(cardBackground)
    }
    
    private var dictyLogoImage: Image {
        if let url = DictyResources.url(forResource: "dicty_tray_icon", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            let scaledImage = nsImage.copy() as! NSImage
            scaledImage.size = NSSize(width: 14, height: 14)
            scaledImage.isTemplate = true
            return Image(nsImage: scaledImage)
        }
        return Image(systemName: "waveform.circle")
    }
}

// MARK: - App Mode Chip View

struct AppModeChipView: View {
    @ObservedObject var engineClient: EngineClient
    @State private var isHovering = false
    
    private var appName: String {
        engineClient.targetApp?.localizedName ?? "Dictation"
    }
    
    private var modeName: String {
        engineClient.effectiveResolvedModeDisplay
    }
    
    var body: some View {
        Menu {
            Section("This recording only") {
                ForEach(availableAppRuleModes) { mode in
                    Button {
                        engineClient.recordingOverrideMode = mode.id
                        engineClient.currentResolvedMode = mode.id
                        engineClient.currentResolvedReason = "manual_override"
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.name)
                            if engineClient.currentResolvedMode == mode.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            if let target = engineClient.targetApp, let bundleId = target.bundleIdentifier {
                Section("Always use in \(appName)") {
                    ForEach(availableAppRuleModes) { mode in
                        Button {
                            if let existing = engineClient.appRules.first(where: { $0.match.type == "bundle_id" && $0.match.value == bundleId }) {
                                engineClient.updateAppRule(id: existing.id, modeId: mode.id, enabled: true)
                            } else {
                                engineClient.createAppRule(matchType: "bundle_id", matchValue: bundleId, modeId: mode.id, displayName: appName)
                            }
                            engineClient.recordingOverrideMode = mode.id
                            engineClient.currentResolvedMode = mode.id
                            engineClient.currentResolvedReason = "app_rule"
                        } label: {
                            HStack {
                                Image(systemName: mode.icon)
                                Text("Always use \(mode.name)")
                            }
                        }
                    }
                    if let existing = engineClient.appRules.first(where: { $0.match.type == "bundle_id" && $0.match.value == bundleId }) {
                        Button(role: .destructive) {
                            engineClient.deleteAppRule(id: existing.id)
                        } label: {
                            Text("Remove rule for \(appName)")
                        }
                    }
                }
            }
            
            if engineClient.manualOverrideActive {
                Section {
                    Button {
                        engineClient.manualOverrideActive = false
                        engineClient.recordingOverrideMode = nil
                        engineClient.resolveCurrentAppRule()
                    } label: {
                        Label("Resume Automatic Mode", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let app = engineClient.targetApp, let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.7))
                }
                Text("\(appName) · \(modeName)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(isHovering ? .white : .white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(isHovering ? Color.appAccent.opacity(0.3) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(isHovering ? Color.appAccent.opacity(0.6) : Color.white.opacity(0.18), lineWidth: 0.8)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("Mode: \(modeName) in \(appName). Click to change for this recording or set a rule.")
    }
}
