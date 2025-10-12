//
//  ContentView.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var accessibilityManager: AccessibilityManager
    @ObservedObject var completionService: CompletionService
    @ObservedObject var audioRecordingManager: AudioRecordingManager

    @State private var apiKey: String = ""
    @State private var showAPIKeyInput = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 4) {
                    Text("Relex")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .tracking(-0.5)

                    Text("AI Text Completion Assistant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                // Permissions Section
                VStack(spacing: 0) {
                    SectionHeader(title: "Permissions")

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

                        PermissionRow(
                            icon: "key.fill",
                            iconColor: !completionService.apiKey.isEmpty ? .green : .orange,
                            title: "OpenAI API Key",
                            status: !completionService.apiKey.isEmpty,
                            statusText: !completionService.apiKey.isEmpty ? "Configured" : "Not Set",
                            buttonText: completionService.apiKey.isEmpty ? "Configure API Key" : "Update API Key",
                            showButton: true,
                            secondaryButtonText: completionService.apiKey.isEmpty ? nil : "Remove"
                        ) {
                            showAPIKeyInput = true
                        } secondaryAction: {
                            completionService.setAPIKey("")
                        }
                    }
                    .padding(14)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

                // Instructions Section
                VStack(spacing: 0) {
                    SectionHeader(title: "How to Use")

                    VStack(alignment: .leading, spacing: 10) {
                        // Text Completion
                        InstructionBlock(
                            title: "Text Completion:",
                            icon: "text.cursor",
                            iconColor: .blue,
                            steps: [
                                ("1", "Press Option + J in any text field"),
                                ("2", "Navigate options with Option + J/K"),
                                ("3", "Drill down with Option + L, back with Option + H"),
                                ("4", "Accept with Option + F, cancel with Escape")
                            ]
                        )

                        Divider()

                        // Voice Dictation
                        InstructionBlock(
                            title: "Voice Dictation:",
                            icon: "waveform",
                            iconColor: .purple,
                            steps: [
                                ("1", "Hold Right Option key to start recording"),
                                ("2", "Speak your text clearly"),
                                ("3", "Release Right Option to transcribe and insert"),
                                ("4", "Press Escape while recording to cancel")
                            ]
                        )
                    }
                    .padding(14)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

                // Footer
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 600, idealWidth: 650, minHeight: 600)
        .sheet(isPresented: $showAPIKeyInput) {
            APIKeyInputView(
                apiKey: $apiKey,
                onSave: {
                    completionService.setAPIKey(apiKey)
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
            apiKey = completionService.apiKey
        }
        .onChange(of: showAPIKeyInput) { _, newValue in
            if newValue {
                // Reload current API key when sheet opens
                apiKey = completionService.apiKey
            }
        }
    }
}

// MARK: - Helper Components

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
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
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(status ? .green : .orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
            .cornerRadius(8)
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
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Configure OpenAI API Key")
                    .font(.headline)

                Text("This key is required for text completions and voice transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

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
    }
}

#Preview {
    ContentView(
        accessibilityManager: AccessibilityManager(),
        completionService: CompletionService(),
        audioRecordingManager: AudioRecordingManager()
    )
}
