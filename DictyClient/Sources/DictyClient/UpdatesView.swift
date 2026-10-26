import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Updates View
struct CheckForUpdatesView: View {
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 60))
                .foregroundColor(updateChecker.updateAvailable ? .stylishGreen : .sageGreen)
                .rotationEffect(Angle(degrees: updateChecker.isChecking ? 360 : 0))
                .animation(updateChecker.isChecking ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: updateChecker.isChecking)
            
            Text("Dicty Updates")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Installed Version:")
                        .foregroundColor(.dictySecondary)
                    Text("v\(updateChecker.currentVersion)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
                
                Button(action: {
                    updateChecker.checkForUpdates(manual: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.dictySecondary)
                .help("Refresh update status")
                .disabled(updateChecker.isChecking)
            }
            
            if updateChecker.isChecking {
                Text("Checking for updates...")
                    .font(.body)
                    .foregroundColor(.dictySecondary)
            } else if let error = updateChecker.lastCheckError {
                Text(error)
                    .font(.body)
                    .foregroundColor(.red)
            } else if updateChecker.updateAvailable {
                VStack(spacing: 8) {
                    Text("A new version of Dicty is available!")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Version \(updateChecker.latestVersion) (You have \(updateChecker.currentVersion))")
                        .font(.body)
                        .foregroundColor(.dictySecondary)
                }
            } else {
                Text("You are on the latest version of Dicty (\(updateChecker.currentVersion)).")
                    .font(.body)
                    .foregroundColor(.dictySecondary)
            }
            
            if updateChecker.updateAvailable {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Release Notes:")
                        .font(.headline)
                        .padding(.top, 10)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            let normalized = updateChecker.releaseNotes.replacingOccurrences(of: "\r\n", with: "\n")
                            let blocks = normalized.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            ForEach(blocks.indices, id: \.self) { index in
                                let block = blocks[index]
                                if let attrString = try? AttributedString(markdown: block, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
                                    Text(attrString)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text(block)
                                        .font(.system(.body, design: .monospaced))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .frame(minHeight: 150, maxHeight: 286)
                }
                .padding(.horizontal, 40)
                
                if updateChecker.isApplying {
                    VStack(spacing: 8) {
                        ProgressView(value: updateChecker.downloadProgress, total: 100.0)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        
                        if updateChecker.downloadProgress >= 100.0 {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Installing update & relaunching...")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        } else {
                            Text("Downloading: \(Int(updateChecker.downloadProgress))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                } else {
                    Button(action: {
                        updateChecker.applyUpdate()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text(updateChecker.downloadURL == nil ? "Preparing Installer..." : "Install Update & Relaunch")
                        }
                    }
                    .buttonStyle(.flatPrimary)
                    .disabled(updateChecker.downloadURL == nil)
                }
                
                if let error = updateChecker.lastCheckError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.top, 4)
                }
            } else {
                Button(action: {
                    updateChecker.checkForUpdates(manual: true)
                }) {
                    HStack(spacing: 6) {
                        if updateChecker.isChecking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking for Updates...")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Check for Updates")
                        }
                    }
                }
                .buttonStyle(.flatPrimary)
                .disabled(updateChecker.isChecking)
            }
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateChecker.checkForUpdates(manual: true)
        }
    }
}
