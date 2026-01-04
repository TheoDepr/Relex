//
//  ContentView.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import SwiftUI

// MARK: - Liquid Glass View Modifier with Backward Compatibility

/// A view modifier that applies Liquid Glass on macOS 26+ with fallback for older versions
struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if isInteractive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            // Fallback for older macOS versions
            content
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        }
    }
}

extension View {
    /// Applies Liquid Glass effect with capsule shape
    func liquidGlassCapsule(interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: Capsule(), isInteractive: interactive))
    }

    /// Applies Liquid Glass effect with rounded rectangle
    func liquidGlassRounded(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius), isInteractive: interactive))
    }

    /// Applies Liquid Glass effect with circle shape
    func liquidGlassCircle(interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: Circle(), isInteractive: interactive))
    }
}

struct ContentView: View {
    @ObservedObject var accessibilityManager: AccessibilityManager
    @ObservedObject var audioRecordingManager: AudioRecordingManager
    @ObservedObject var transcriptionService: TranscriptionService
    @ObservedObject var gptService: GPTService

    @State private var apiKey: String = ""
    @State private var showAPIKeyInput = false
    @State private var usageStatistics = UsageTracker.shared.getStatistics()
    @State private var gptStatistics = UsageTracker.shared.getGPTStatistics()
    @State private var usageObserver: NSObjectProtocol?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with Liquid Glass
                VStack(spacing: 4) {
                    Text("Relex")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .tracking(-0.5)

                    Text("Voice Dictation Assistant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .liquidGlassCapsule(interactive: true)
                .padding(.bottom, 4)

                // Instructions Section
                GlassSection {
                    SectionHeader(title: "How to Use", icon: "book.fill", iconColor: .blue)

                    VStack(alignment: .leading, spacing: 16) {
                        // Voice Dictation
                        InstructionBlock(
                            title: "Voice Dictation (No Selection):",
                            icon: "waveform",
                            iconColor: .purple,
                            steps: [
                                ("1", "Click in any text field (no text selected)"),
                                ("2", "Hold Right Option key to start recording"),
                                ("3", "Speak your text clearly"),
                                ("4", "Release Right Option to transcribe and insert")
                            ]
                        )

                        Divider()
                            .opacity(0.5)

                        // AI Text Commands
                        InstructionBlock(
                            title: "AI Text Commands (With Selection):",
                            icon: "wand.and.stars",
                            iconColor: .orange,
                            steps: [
                                ("1", "Select/highlight text you want to transform"),
                                ("2", "Hold Right Option key to start recording"),
                                ("3", "Say a command (e.g., \"make this formal\")"),
                                ("4", "Release Right Option - GPT transforms the text")
                            ]
                        )

                        Text("Press Escape anytime to cancel")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }

                // Permissions Section
                GlassSection {
                    SectionHeader(title: "Permissions", icon: "shield.fill", iconColor: .green)

                    VStack(spacing: 0) {
                        PermissionRow(
                            icon: "checkmark.shield.fill",
                            iconColor: accessibilityManager.isAccessibilityGranted ? .green : .orange,
                            title: "Accessibility Access",
                            status: accessibilityManager.isAccessibilityGranted,
                            statusText: accessibilityManager.isAccessibilityGranted ? "Granted" : "Required",
                            buttonText: "Request Accessibility Access",
                            showButton: !accessibilityManager.isAccessibilityGranted
                        ) {
                            accessibilityManager.requestAccessibility()
                        }

                        Divider()
                            .padding(.leading, 48)
                            .opacity(0.5)

                        PermissionRow(
                            icon: "mic.fill",
                            iconColor: audioRecordingManager.isMicrophoneGranted ? .green : .orange,
                            title: "Microphone Access",
                            status: audioRecordingManager.isMicrophoneGranted,
                            statusText: audioRecordingManager.isMicrophoneGranted ? "Granted" : "Required",
                            buttonText: "Request Microphone Access",
                            showButton: !audioRecordingManager.isMicrophoneGranted
                        ) {
                            audioRecordingManager.requestMicrophonePermission()
                        }

                        Divider()
                            .padding(.leading, 48)
                            .opacity(0.5)

                        PermissionRow(
                            icon: "key.fill",
                            iconColor: !transcriptionService.apiKey.isEmpty ? .green : .orange,
                            title: "OpenAI API Key",
                            status: !transcriptionService.apiKey.isEmpty,
                            statusText: !transcriptionService.apiKey.isEmpty ? "Configured" : "Not Set",
                            buttonText: transcriptionService.apiKey.isEmpty ? "Configure API Key" : "Update API Key",
                            showButton: true,
                            secondaryButtonText: transcriptionService.apiKey.isEmpty ? nil : "Remove"
                        ) {
                            showAPIKeyInput = true
                        } secondaryAction: {
                            transcriptionService.setAPIKey("")
                        }
                    }
                    .padding(14)
                }

                // Model Selection Section
                GlassSection {
                    SectionHeader(title: "Models", icon: "cpu.fill", iconColor: .purple)

                    VStack(spacing: 16) {
                        // Transcription Model Selection
                        HStack(spacing: 12) {
                            GlassIconBadge(icon: "waveform", color: .purple)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Transcription Model")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("For voice-to-text")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker("", selection: $transcriptionService.selectedModel) {
                                ForEach(WhisperModel.allCases, id: \.self) { model in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.body)
                                        Text(model.description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 250)
                        }

                        Divider()
                            .opacity(0.5)

                        // GPT Model Selection
                        HStack(spacing: 12) {
                            GlassIconBadge(icon: "wand.and.stars", color: .orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("GPT Model")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("For text commands")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Picker("", selection: $gptService.selectedModel) {
                                ForEach(GPTModel.allCases, id: \.self) { model in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.body)
                                        Text(model.description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 250)
                        }
                    }
                    .padding(14)
                }

                // Usage Statistics Section
                GlassSection {
                    SectionHeader(title: "Usage Statistics", icon: "chart.bar.fill", iconColor: .cyan)

                    VStack(spacing: 16) {
                        // Transcription Usage
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                GlassIconBadge(icon: "chart.bar.fill", color: .purple)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Transcription Usage")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text("Voice-to-text costs")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    UsageTracker.shared.resetUsage()
                                    refreshUsageStats()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Reset All")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // Statistics Grid with Glass Cards
                            HStack(spacing: 12) {
                                GlassStatCard(
                                    title: "Cost",
                                    value: String(format: "$%.4f", usageStatistics.totalCost),
                                    icon: "dollarsign.circle.fill",
                                    color: .green
                                )

                                GlassStatCard(
                                    title: "Requests",
                                    value: "\(usageStatistics.totalRequests)",
                                    icon: "mic.circle.fill",
                                    color: .blue
                                )

                                GlassStatCard(
                                    title: "Minutes",
                                    value: String(format: "%.1f", usageStatistics.totalMinutes),
                                    icon: "clock.fill",
                                    color: .purple
                                )
                            }
                        }

                        Divider()
                            .opacity(0.5)

                        // GPT Usage
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                GlassIconBadge(icon: "sparkles", color: .orange)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("GPT Usage")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text("Text command costs")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }

                            // Statistics Grid with Glass Cards
                            HStack(spacing: 12) {
                                GlassStatCard(
                                    title: "Cost",
                                    value: String(format: "$%.4f", gptStatistics.totalCost),
                                    icon: "dollarsign.circle.fill",
                                    color: .green
                                )

                                GlassStatCard(
                                    title: "Commands",
                                    value: "\(gptStatistics.totalRequests)",
                                    icon: "wand.and.stars",
                                    color: .orange
                                )

                                GlassStatCard(
                                    title: "Tokens",
                                    value: String(format: "%.0fk", Double(gptStatistics.totalTokens) / 1000.0),
                                    icon: "number.circle.fill",
                                    color: .blue
                                )
                            }
                        }
                    }
                    .padding(14)
                }

                // Footer
                VStack(spacing: 4) {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Version \(version)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Made by Theo Depraetere")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .liquidGlassCapsule()
                .padding(.top, 4)
            }
            .padding(24)
        }
        .background {
            // Ambient gradient background to make glass effects pop
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.08),
                    Color.blue.opacity(0.05),
                    Color.orange.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .frame(minWidth: 480, idealWidth: 480, minHeight: 650, maxHeight: 650)
        .sheet(isPresented: $showAPIKeyInput) {
            APIKeyInputView(
                apiKey: $apiKey,
                onSave: {
                    transcriptionService.setAPIKey(apiKey)
                    showAPIKeyInput = false
                }
            )
        }
        .onAppear {
            // Migrate API key from UserDefaults to Keychain if needed
            KeychainManager.shared.migrateFromUserDefaults()

            accessibilityManager.checkAccessibility()
            audioRecordingManager.checkMicrophonePermission()
            // Load existing API key if present
            apiKey = transcriptionService.apiKey

            // Load usage stats
            refreshUsageStats()

            // Post notification that settings window has opened
            NotificationCenter.default.post(name: NSNotification.Name("SettingsWindowOpened"), object: nil)

            // Listen for usage stats updates (event-driven, no polling)
            // Store the observer reference so we can properly remove it later
            usageObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UsageStatsUpdated"),
                object: nil,
                queue: .main
            ) { _ in
                refreshUsageStats()
            }
        }
        .onDisappear {
            // Post notification that settings window has closed
            NotificationCenter.default.post(name: NSNotification.Name("SettingsWindowClosed"), object: nil)

            // Remove observer using the stored reference
            if let observer = usageObserver {
                NotificationCenter.default.removeObserver(observer)
                usageObserver = nil
            }
        }
        .onChange(of: showAPIKeyInput) { _, newValue in
            if newValue {
                // Reload current API key when sheet opens
                apiKey = transcriptionService.apiKey
            }
        }
    }

    private func refreshUsageStats() {
        usageStatistics = UsageTracker.shared.getStatistics()
        gptStatistics = UsageTracker.shared.getGPTStatistics()
    }
}

// MARK: - Liquid Glass Components

/// A container that applies the Liquid Glass effect to its content
struct GlassSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .liquidGlassRounded(cornerRadius: 16)
    }
}

/// Icon badge with glass effect
struct GlassIconBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .liquidGlassRounded(cornerRadius: 8)
    }
}

/// Stat card with liquid glass effect
struct GlassStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlassRounded(cornerRadius: 10)
    }
}

// MARK: - Helper Components

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.3))
    }
}

struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let status: Bool
    let statusText: String
    let buttonText: String
    let showButton: Bool
    var secondaryButtonText: String? = nil
    let action: () -> Void
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(8)

                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                StatusBadge(status: status, text: statusText)
            }

            if showButton {
                HStack(spacing: 8) {
                    Button(action: action) {
                        Text(buttonText)
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if let secondaryText = secondaryButtonText,
                       let secondaryAction = secondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryText)
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatusBadge: View {
    let status: Bool
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(status ? .green : .orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlassCapsule()
    }
}

struct InstructionBlock: View {
    let title: String
    let icon: String
    let iconColor: Color
    let steps: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(steps, id: \.0) { step in
                    HStack(alignment: .top, spacing: 6) {
                        Text(step.0)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .frame(width: 16, alignment: .leading)
                        Text(step.1)
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.leading, 2)
        }
    }
}


struct APIKeyInputView: View {
    @Binding var apiKey: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            // Icon with glass effect
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .liquidGlassCircle(interactive: true)

                Text("Configure OpenAI API Key")
                    .font(.headline)

                Text("This key is required for voice transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            // Input section with glass container
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)

                Button(action: {
                    openURL(URL(string: "https://platform.openai.com/api-keys")!)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                        Text("Get an API key from OpenAI")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            .padding(16)
            .liquidGlassRounded(cornerRadius: 12)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 450)
        .background {
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.06),
                    Color.purple.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    ContentView(
        accessibilityManager: AccessibilityManager(),
        audioRecordingManager: AudioRecordingManager(),
        transcriptionService: TranscriptionService(),
        gptService: GPTService()
    )
}
