//
//  AudioRecordingManager.swift
//  Relex
//
//  Created by Theo Depraetere on 09/10/2025.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class AudioRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isMicrophoneGranted = false
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastError: String?

    private var audioRecorder: AVAudioRecorder?
    private var audioLevelTimer: Timer?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var recordingURL: URL?

    override init() {
        super.init()
        checkMicrophonePermission()
    }

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophoneGranted = true
        case .notDetermined, .denied, .restricted:
            isMicrophoneGranted = false
        @unknown default:
            isMicrophoneGranted = false
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.isMicrophoneGranted = granted
                if granted {
                    print("✅ Microphone permission granted")
                } else {
                    print("❌ Microphone permission denied")
                }
            }
        }
    }

    func startRecording() -> URL? {
        guard isMicrophoneGranted else {
            lastError = "Microphone permission not granted"
            print("❌ Cannot start recording: microphone permission not granted")
            return nil
        }

        // Prevent starting a new recording if one is already in progress
        if isRecording {
            print("⚠️ Recording already in progress, ignoring start request")
            return recordingURL
        }

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "relex_recording_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordingURL = fileURL

        // Note: AVAudioSession is iOS-only, macOS doesn't require session configuration

        // Configure recording settings (M4A format)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0, // Whisper prefers 16kHz
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0

            // Start monitoring audio levels
            startAudioLevelMonitoring()
            startDurationTimer()

            print("✅ Started recording to: \(fileURL.lastPathComponent)")
            return fileURL
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
            print("❌ Recording error: \(error)")
            return nil
        }
    }

    func stopRecording() -> URL? {
        guard isRecording, let recorder = audioRecorder else {
            print("⚠️ No active recording to stop")
            return nil
        }

        recorder.stop()
        isRecording = false

        // Stop timers
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil

        // Note: No audio session cleanup needed on macOS

        audioLevel = 0.0

        let finalURL = recordingURL

        // Clear recorder reference
        audioRecorder = nil

        print("✅ Stopped recording, duration: \(String(format: "%.1f", recordingDuration))s")
        return finalURL
    }

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self = self, let recorder = self.audioRecorder else { return }

                recorder.updateMeters()
                let averagePower = recorder.averagePower(forChannel: 0)

                // Convert dB to 0.0-1.0 range (dB range is typically -60 to 0)
                let normalizedLevel = max(0.0, min(1.0, (averagePower + 60) / 60))
                self.audioLevel = normalizedLevel
            }
        }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    func cleanupRecording(at url: URL?) {
        guard let url = url else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("🗑️ Cleaned up recording file: \(url.lastPathComponent)")
            }
        } catch {
            print("⚠️ Failed to cleanup recording file: \(error)")
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecordingManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("🎙️ Recording finished, success: \(flag)")
        if !flag {
            Task { @MainActor in
                self.lastError = "Recording failed"
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Recording encode error: \(error?.localizedDescription ?? "unknown")")
        Task { @MainActor in
            self.lastError = error?.localizedDescription ?? "Recording encode error"
        }
    }
}
