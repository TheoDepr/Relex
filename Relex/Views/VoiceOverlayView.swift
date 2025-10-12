//
//  VoiceOverlayView.swift
//  Relex
//
//  Created by Theo Depraetere on 09/10/2025.
//

import SwiftUI
import Combine

@MainActor
class VoiceOverlayViewModel: ObservableObject {
    @Published var isVisible = false
    @Published var state: VoiceState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?

    private let audioRecordingManager: AudioRecordingManager
    private let transcriptionService: TranscriptionService
    private let accessibilityManager: AccessibilityManager
    weak var windowManager: VoiceOverlayWindowManager?

    private var recordingFileURL: URL?
    private var capturedContext: String?

    init(audioRecordingManager: AudioRecordingManager,
         transcriptionService: TranscriptionService,
         accessibilityManager: AccessibilityManager) {
        self.audioRecordingManager = audioRecordingManager
        self.transcriptionService = transcriptionService
        self.accessibilityManager = accessibilityManager
    }

    func startRecording() async {
        print("🎤 VoiceOverlayViewModel: Starting recording")

        // If we're in any non-idle state, reset first
        if state != .idle {
            print("⚠️ Resetting state from \(state) to idle before starting new recording")
            hide()
        }

        // Capture context from focused element (optional - only used to improve transcription)
        capturedContext = await accessibilityManager.captureTextFromFocusedElement()
        if let context = capturedContext, !context.isEmpty {
            print("📝 Captured context for transcription hint: \(context.prefix(100))...")
        } else {
            print("📝 No context captured (empty field) - transcription will work without hint")
        }

        // Show overlay
        isVisible = true
        state = .recording
        error = nil

        // Start recording
        recordingFileURL = audioRecordingManager.startRecording()

        if recordingFileURL == nil {
            error = audioRecordingManager.lastError ?? "Failed to start recording"
            state = .error

            // Auto-hide after showing error briefly
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if state == .error {
                        hide()
                        windowManager?.hideOverlay()
                    }
                }
            }
        }
    }

    func stopRecordingAndTranscribe() async {
        print("🛑 VoiceOverlayViewModel: Stopping recording")

        guard state == .recording else {
            print("⚠️ Not in recording state, ignoring")
            return
        }

        // Check minimum recording duration (0.5 seconds)
        let recordedDuration = audioRecordingManager.recordingDuration
        if recordedDuration < 0.5 {
            print("⏭️ Recording too short (\(String(format: "%.2f", recordedDuration))s), ignoring")

            // Stop and cleanup
            if let audioURL = audioRecordingManager.stopRecording() {
                audioRecordingManager.cleanupRecording(at: audioURL)
            }

            // Hide without error
            hide()
            windowManager?.hideOverlay()
            return
        }

        // Stop recording
        guard let audioURL = audioRecordingManager.stopRecording() else {
            error = "Failed to stop recording"
            state = .error

            // Auto-hide after showing error briefly
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if state == .error {
                        hide()
                        windowManager?.hideOverlay()
                    }
                }
            }
            return
        }

        // Update state to transcribing
        state = .transcribing

        // Transcribe audio
        do {
            let transcribedText = try await transcriptionService.transcribe(
                audioFileURL: audioURL,
                context: capturedContext
            )

            print("✅ Transcription complete: \"\(transcribedText)\"")

            // Insert transcribed text
            print("📝 Attempting to insert transcribed text: \"\(transcribedText)\"")
            let success = await accessibilityManager.insertText(transcribedText)

            if success {
                print("✅ Text inserted successfully")
                hide()
                windowManager?.hideOverlay()
            } else {
                let errorMsg = accessibilityManager.lastError ?? "Failed to insert text"
                print("❌ Insert failed: \(errorMsg)")
                error = "Insert failed: \(errorMsg)"
                state = .error

                // Auto-hide after showing error briefly
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    await MainActor.run {
                        if state == .error {
                            hide()
                            windowManager?.hideOverlay()
                        }
                    }
                }
            }

            // Cleanup audio file
            audioRecordingManager.cleanupRecording(at: audioURL)

        } catch {
            print("❌ Transcription error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            state = .error

            // Cleanup audio file
            audioRecordingManager.cleanupRecording(at: audioURL)

            // Auto-hide after showing error briefly
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if state == .error {
                        hide()
                        windowManager?.hideOverlay()
                    }
                }
            }
        }
    }

    func hide() {
        isVisible = false
        state = .idle
        error = nil
        audioLevel = 0.0
        recordingDuration = 0
        recordingFileURL = nil
        capturedContext = nil
    }

    func cancel() {
        print("🚫 Canceling voice recording")

        if state == .recording {
            if let audioURL = audioRecordingManager.stopRecording() {
                audioRecordingManager.cleanupRecording(at: audioURL)
            }
        }

        hide()
        windowManager?.hideOverlay()
    }
}

enum VoiceState {
    case idle
    case recording
    case transcribing
    case error
}

struct VoiceOverlayView: View {
    @ObservedObject var viewModel: VoiceOverlayViewModel
    @ObservedObject var audioManager: AudioRecordingManager

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                EmptyView()

            case .recording:
                // Just waveform - minimalistic
                WaveformView(audioLevel: audioManager.audioLevel)
                    .frame(width: 200, height: 30)

            case .transcribing:
                // Pulsing dots animation
                PulsingDotsView()
                    .frame(width: 200, height: 30)

            case .error:
                // Just error icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                    .frame(width: 200, height: 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, milliseconds)
    }
}

struct WaveformView: View {
    let audioLevel: Float
    let barCount = 30

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    audioLevel: audioLevel,
                    index: index,
                    totalBars: barCount
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

struct WaveformBar: View {
    let audioLevel: Float
    let index: Int
    let totalBars: Int

    var body: some View {
        let normalizedIndex = Float(index) / Float(totalBars)
        let centerDistance = abs(normalizedIndex - 0.5) * 2 // 0 at center, 1 at edges

        // Create wave effect - bars in middle are taller
        let baseHeight: CGFloat = 3
        let waveMultiplier = 1.0 - CGFloat(centerDistance * 0.7)

        let audioMultiplier = CGFloat(audioLevel) * 0.8 + 0.2 // Min 0.2, max 1.0
        let height = baseHeight + (24 * waveMultiplier * audioMultiplier)

        return RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    colors: [.red, .blue],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: height)
            .animation(.easeInOut(duration: 0.1), value: audioLevel)
    }
}

#Preview("Recording State") {
    let audioManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let accessibilityManager = AccessibilityManager()

    let viewModel = VoiceOverlayViewModel(
        audioRecordingManager: audioManager,
        transcriptionService: transcriptionService,
        accessibilityManager: accessibilityManager
    )

    viewModel.isVisible = true
    viewModel.state = .recording
    audioManager.audioLevel = 0.6
    audioManager.recordingDuration = 3.5

    return VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        .frame(width: 400, height: 300)
}

#Preview("Transcribing State") {
    let audioManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let accessibilityManager = AccessibilityManager()

    let viewModel = VoiceOverlayViewModel(
        audioRecordingManager: audioManager,
        transcriptionService: transcriptionService,
        accessibilityManager: accessibilityManager
    )

    viewModel.isVisible = true
    viewModel.state = .transcribing

    return VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        .frame(width: 400, height: 300)
}
