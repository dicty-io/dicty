import SwiftUI
import AppKit

struct UpdateNotificationView: View {
    @EnvironmentObject var engineClient: EngineClient
    @EnvironmentObject var updateChecker: UpdateChecker
    
    var closeAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.appAccent)
                
                Text("Dicty Update Available")
                    .font(.system(size: 15, weight: .bold))
                
                Spacer()
                
                Button(action: closeAction) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(updateChecker.isApplying)
            }
            
            Text("A new version of Dicty (\(updateChecker.latestVersion)) is now available. You are currently running \(updateChecker.currentVersion).")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            
            if updateChecker.isApplying {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: updateChecker.downloadProgress, total: 100.0)
                        .progressViewStyle(.linear)
                    
                    HStack(spacing: 6) {
                        if updateChecker.downloadProgress >= 100.0 {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Installing update & relaunching...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        } else {
                            Text("Downloading update: \(Int(updateChecker.downloadProgress))%")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 2)
            }
            
            if let error = updateChecker.lastCheckError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            
            HStack(spacing: 10) {
                Button("Later") {
                    closeAction()
                }
                .buttonStyle(.flatSecondary)
                .disabled(updateChecker.isApplying)
                
                Spacer()
                
                Button("View Notes") {
                    closeAction()
                    WindowManager.openSettingsWindow(engineClient: engineClient, tabIndex: 14)
                }
                .buttonStyle(.flatSecondary)
                
                Button(action: {
                    updateChecker.applyUpdate()
                }) {
                    HStack(spacing: 6) {
                        if updateChecker.isApplying {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Update Now")
                        }
                    }
                }
                .buttonStyle(.flatPrimary)
                .disabled(updateChecker.isApplying)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 390)
    }
}

