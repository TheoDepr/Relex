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
    @Published var mode: VoiceMode = .dictation

    private let audioRecordingManager: AudioRecordingManager
    private let transcriptionService: TranscriptionService
    private let gptService: GPTService
    private let accessibilityManager: AccessibilityManager
    weak var windowManager: VoiceOverlayWindowManager?

    private var recordingFileURL: URL?
    private var capturedContext: String?
    private var selectedText: String?
    private var transcriptionTask: Task<Void, Never>?

    init(audioRecordingManager: AudioRecordingManager,
         transcriptionService: TranscriptionService,
         gptService: GPTService,
         accessibilityManager: AccessibilityManager) {
        self.audioRecordingManager = audioRecordingManager
        self.transcriptionService = transcriptionService
        self.gptService = gptService
        self.accessibilityManager = accessibilityManager
    }

    func startRecording() async {
        print("🎤 VoiceOverlayViewModel: Starting recording")

        // If we're in any non-idle state, reset first
        if state != .idle {
            print("⚠️ Resetting state from \(state) to idle before starting new recording")
            hide()
        }

        // Capture context/selected text from focused element
        capturedContext = await accessibilityManager.captureTextFromFocusedElement()

        // Determine mode based on whether text is selected
        if let context = capturedContext, !context.isEmpty {
            // Command mode: text is selected
            mode = .command
            selectedText = context
            print("🎯 COMMAND MODE activated - selected text: \"\(context.prefix(100))...\"")
        } else {
            // Dictation mode: no selection
            mode = .dictation
            selectedText = nil
            capturedContext = nil
            print("📝 DICTATION MODE activated - no selection")
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
            let (audioURL, _) = audioRecordingManager.stopRecording()
            if let audioURL = audioURL {
                audioRecordingManager.cleanupRecording(at: audioURL)
            }

            // Hide without error
            hide()
            windowManager?.hideOverlay()
            return
        }

        // Stop recording
        let (audioURL, audioDuration) = audioRecordingManager.stopRecording()
        guard let audioURL = audioURL else {
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

        // Update state based on mode
        if mode == .command {
            state = .commandProcessing
            print("🎯 Processing voice command...")
        } else {
            state = .transcribing
            print("📝 Transcribing voice...")
        }

        // Process audio in a cancellable task
        transcriptionTask = Task { @MainActor in
            do {
                // First, transcribe the voice command/dictation
                let transcribedText = try await transcriptionService.transcribe(
                    audioFileURL: audioURL,
                    context: mode == .dictation ? capturedContext : nil,  // Only use context for dictation mode
                    durationSeconds: audioDuration
                )

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("⚠️ Transcription was cancelled")
                    audioRecordingManager.cleanupRecording(at: audioURL)
                    return
                }

                print("✅ Transcription complete: \"\(transcribedText)\"")

                // Now process based on mode
                let finalText: String
                if mode == .command {
                    // Command mode: Send selected text + voice command to GPT
                    guard let selected = selectedText else {
                        throw GPTError.emptySelectedText
                    }

                    print("🎯 Sending to GPT for processing...")
                    print("   Selected text: \"\(selected.prefix(100))...\"")
                    print("   Voice command: \"\(transcribedText)\"")

                    finalText = try await gptService.processTextCommand(
                        selectedText: selected,
                        voiceCommand: transcribedText
                    )

                    print("✅ GPT processing complete")
                    print("   Result length: \(finalText.count) chars")
                } else {
                    // Dictation mode: Use transcribed text directly
                    finalText = transcribedText
                }

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("⚠️ Processing was cancelled")
                    audioRecordingManager.cleanupRecording(at: audioURL)
                    return
                }

                // Insert final text (will replace selection in command mode)
                print("📝 Attempting to insert final text: \"\(finalText.prefix(100))...\"")
                let success = await accessibilityManager.insertText(finalText)

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
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("⚠️ Processing was cancelled")
                    audioRecordingManager.cleanupRecording(at: audioURL)
                    return
                }

                print("❌ Processing error: \(error.localizedDescription)")
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
    }

    func hide() {
        isVisible = false
        state = .idle
        error = nil
        audioLevel = 0.0
        recordingDuration = 0
        recordingFileURL = nil
        capturedContext = nil
        selectedText = nil
        mode = .dictation

        // Cancel any ongoing transcription/processing
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Notify that the voice operation is complete
        NotificationCenter.default.post(name: .voiceOperationCompleted, object: nil)
    }

    func cancel() {
        print("🚫 Canceling voice operation (state: \(state), mode: \(mode))")

        if state == .recording {
            // Cancel recording
            let (audioURL, _) = audioRecordingManager.stopRecording()
            if let audioURL = audioURL {
                audioRecordingManager.cleanupRecording(at: audioURL)
            }
        } else if state == .transcribing || state == .commandProcessing {
            // Cancel transcription/processing task
            print("⚠️ Canceling ongoing \(state == .commandProcessing ? "command processing" : "transcription")")
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }

        hide()
        windowManager?.hideOverlay()
    }
}

enum VoiceState {
    case idle
    case recording
    case transcribing
    case commandProcessing
    case error
}

enum VoiceMode {
    case dictation  // Insert new text
    case command    // Transform selected text
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
                // Show waveform with mode-specific colors
                if viewModel.mode == .command {
                    // Command mode: red/yellow colors (red bottom, yellow top)
                    WaveformView(audioLevel: audioManager.audioLevel, colors: [.red, .yellow])
                        .frame(width: 200, height: 30)
                } else {
                    // Dictation mode: purple/blue colors (purple bottom, blue top)
                    WaveformView(audioLevel: audioManager.audioLevel, colors: [.purple, .blue])
                        .frame(width: 200, height: 30)
                }

            case .transcribing:
                // Pulsing dots animation - color based on mode
                if viewModel.mode == .command {
                    // Command mode: deep orange/yellow
                    PulsingDotsView(colors: [.red, .yellow])
                        .frame(width: 200, height: 30)
                } else {
                    // Dictation mode: purple/blue
                    PulsingDotsView(colors: [.purple, .blue])
                        .frame(width: 200, height: 30)
                }

            case .commandProcessing:
                // Pulsing dots animation (deep orange/yellow for command)
                PulsingDotsView(colors: [.red, .yellow])
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
    let colors: [Color]
    let barCount = 30

    init(audioLevel: Float, colors: [Color] = [.blue, .purple]) {
        self.audioLevel = audioLevel
        self.colors = colors
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    audioLevel: audioLevel,
                    index: index,
                    totalBars: barCount,
                    colors: colors
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
    let colors: [Color]

    init(audioLevel: Float, index: Int, totalBars: Int, colors: [Color] = [.blue, .purple]) {
        self.audioLevel = audioLevel
        self.index = index
        self.totalBars = totalBars
        self.colors = colors
    }

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
                    colors: colors,
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: height)
            .animation(.easeInOut(duration: 0.1), value: audioLevel)
    }
}

struct PulsingDotsView: View {
    @State private var isAnimating = false
    let colors: [Color]

    init(colors: [Color] = [.blue, .purple]) {
        self.colors = colors
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 10, height: 10)
                    .scaleEffect(isAnimating ? 1.5 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview("Recording State - Dictation") {
    let audioManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let gptService = GPTService()
    let accessibilityManager = AccessibilityManager()

    let viewModel = VoiceOverlayViewModel(
        audioRecordingManager: audioManager,
        transcriptionService: transcriptionService,
        gptService: gptService,
        accessibilityManager: accessibilityManager
    )

    viewModel.isVisible = true
    viewModel.state = .recording
    viewModel.mode = .dictation
    audioManager.audioLevel = 0.6
    audioManager.recordingDuration = 3.5

    return VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        .frame(width: 400, height: 300)
}

#Preview("Recording State - Command") {
    let audioManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let gptService = GPTService()
    let accessibilityManager = AccessibilityManager()

    let viewModel = VoiceOverlayViewModel(
        audioRecordingManager: audioManager,
        transcriptionService: transcriptionService,
        gptService: gptService,
        accessibilityManager: accessibilityManager
    )

    viewModel.isVisible = true
    viewModel.state = .recording
    viewModel.mode = .command
    audioManager.audioLevel = 0.6
    audioManager.recordingDuration = 3.5

    return VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        .frame(width: 400, height: 300)
}

#Preview("Transcribing State") {
    let audioManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let gptService = GPTService()
    let accessibilityManager = AccessibilityManager()

    let viewModel = VoiceOverlayViewModel(
        audioRecordingManager: audioManager,
        transcriptionService: transcriptionService,
        gptService: gptService,
        accessibilityManager: accessibilityManager
    )

    viewModel.isVisible = true
    viewModel.state = .transcribing

    return VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        .frame(width: 400, height: 300)
}

#Preview("Command Processing State") {
    let audioManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let gptService = GPTService()
    let accessibilityManager = AccessibilityManager()

    let viewModel = VoiceOverlayViewModel(
        audioRecordingManager: audioManager,
        transcriptionService: transcriptionService,
        gptService: gptService,
        accessibilityManager: accessibilityManager
    )

    viewModel.isVisible = true
    viewModel.state = .commandProcessing

    return VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        .frame(width: 400, height: 300)
}
