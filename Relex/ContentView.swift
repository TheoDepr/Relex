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
        VStack(spacing: 20) {
            // App Icon & Title
            Image(systemName: "sparkles.rectangle.stack")
                .imageScale(.large)
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Relex")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI Text Completion Assistant")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .padding(.vertical)

            // Status Section
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    icon: "checkmark.shield.fill",
                    title: "Accessibility Access",
                    status: accessibilityManager.isAccessibilityGranted,
                    statusText: accessibilityManager.isAccessibilityGranted ? "Granted" : "Required"
                )

                if !accessibilityManager.isAccessibilityGranted {
                    Button("Request Accessibility Access") {
                        accessibilityManager.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                StatusRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    status: audioRecordingManager.isMicrophoneGranted,
                    statusText: audioRecordingManager.isMicrophoneGranted ? "Granted" : "Required"
                )

                if !audioRecordingManager.isMicrophoneGranted {
                    Button("Request Microphone Access") {
                        audioRecordingManager.requestMicrophonePermission()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                StatusRow(
                    icon: "key.fill",
                    title: "OpenAI API Key",
                    status: !completionService.apiKey.isEmpty,
                    statusText: !completionService.apiKey.isEmpty ? "Configured" : "Not Set"
                )

                HStack(spacing: 8) {
                    Button(completionService.apiKey.isEmpty ? "Configure API Key" : "Update API Key") {
                        showAPIKeyInput = true
                    }
                    .buttonStyle(.borderedProminent)

                    if !completionService.apiKey.isEmpty {
                        Button("Remove") {
                            completionService.setAPIKey("")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to Use")
                    .font(.headline)

                Text("**Text Completion:**")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("1. Press **Option + 0** in any text field")
                Text("2. Wait for AI suggestion to appear")
                Text("3. Press **Option + [** to accept, **Escape** to cancel")

                Text("**Voice Dictation:**")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 8)
                Text("1. **Hold Right Option** key to start recording")
                Text("2. Speak your text")
                Text("3. **Release Right Option** to transcribe and insert")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)

            Spacer()
        }
        .padding(30)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 600)
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

struct StatusRow: View {
    let icon: String
    let title: String
    let status: Bool
    let statusText: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(status ? .green : .orange)
                .frame(width: 24)

            Text(title)
                .font(.body)

            Spacer()

            Text(statusText)
                .font(.caption)
                .foregroundColor(status ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                .cornerRadius(6)
        }
    }
}

struct APIKeyInputView: View {
    @Binding var apiKey: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Configure OpenAI API Key")
                .font(.headline)

            SecureField("Enter your API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding(30)
    }
}

#Preview {
    ContentView(
        accessibilityManager: AccessibilityManager(),
        completionService: CompletionService(),
        audioRecordingManager: AudioRecordingManager()
    )
}
