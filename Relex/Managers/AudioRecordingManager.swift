//
//  AudioRecordingManager.swift
//  Relex
//
//  Created by Theo Depraetere on 09/10/2025.
//

import Foundation
import AVFoundation
import Combine
import AppKit

@MainActor
class AudioRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isMicrophoneGranted = false
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastError: String?

    private var audioRecorder: AVAudioRecorder?
    private var audioLevelTimer: DispatchSourceTimer?
    private var recordingStartTime: Date?
    private var durationTimer: DispatchSourceTimer?
    private var recordingURL: URL?

    override init() {
        super.init()
        
        // Sync with shared PermissionMonitor
        isMicrophoneGranted = PermissionMonitor.shared.isMicrophoneGranted
        
        // Observe permission changes from shared monitor
        NotificationCenter.default.addObserver(
            forName: .microphonePermissionGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.isMicrophoneGranted = true
            }
        }
        
        // Also listen for general permission check updates
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.isMicrophoneGranted = PermissionMonitor.shared.isMicrophoneGranted
            }
        }
    }

    deinit {
        // Clean up timers directly in deinit (nonisolated context)
        audioLevelTimer?.cancel()
        durationTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// Check and sync microphone permission status with shared PermissionMonitor
    func checkMicrophonePermission() {
        PermissionMonitor.shared.checkAllPermissions()
        isMicrophoneGranted = PermissionMonitor.shared.isMicrophoneGranted
    }

    /// Request microphone permission via shared PermissionMonitor
    func requestMicrophonePermission() {
        PermissionMonitor.shared.requestMicrophone()
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

    func stopRecording() -> (url: URL?, duration: TimeInterval) {
        guard isRecording, let recorder = audioRecorder else {
            print("⚠️ No active recording to stop")
            return (nil, 0)
        }

        recorder.stop()
        isRecording = false

        // Stop audio level timer
        stopAudioLevelTimer()
        
        // Stop duration timer
        durationTimer?.cancel()
        durationTimer = nil

        // Note: No audio session cleanup needed on macOS

        audioLevel = 0.0

        let finalURL = recordingURL
        let finalDuration = recordingDuration

        // Clear recorder reference
        audioRecorder = nil

        print("✅ Stopped recording, duration: \(String(format: "%.1f", finalDuration))s")
        return (finalURL, finalDuration)
    }

    func getAudioDuration(from url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            return duration
        } catch {
            print("⚠️ Failed to get audio duration: \(error)")
            // Fallback to recorded duration if available
            return recordingDuration
        }
    }

    private func startAudioLevelMonitoring() {
        // Use high-precision DispatchSourceTimer for audio level updates
        // 60ms interval (~16.6 Hz) provides smooth visual feedback
        // with threshold-based updates to reduce unnecessary SwiftUI refreshes
        startAudioLevelTimer()
    }
    
    private func startAudioLevelTimer() {
        // Clean up any existing timer
        stopAudioLevelTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 60ms interval for smooth visual feedback (~16.6 Hz)
        timer.schedule(deadline: .now(), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            self?.updateAudioLevel()
        }
        timer.resume()
        audioLevelTimer = timer
        print("✅ Audio level timer started")
    }
    
    private func stopAudioLevelTimer() {
        audioLevelTimer?.cancel()
        audioLevelTimer = nil
    }
    
    /// Updates audio level with threshold-based debouncing
    private func updateAudioLevel() {
        guard let recorder = audioRecorder else { return }
        
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        
        // Convert dB to 0.0-1.0 range (dB range is typically -60 to 0)
        let normalizedLevel = max(0.0, min(1.0, (averagePower + 60) / 60))
        
        // Only update if change is noticeable (> 2%) to reduce @Published updates
        // This reduces unnecessary SwiftUI view updates
        if abs(normalizedLevel - audioLevel) > 0.02 {
            audioLevel = normalizedLevel
        }
    }

    private func startDurationTimer() {
        // Use DispatchSourceTimer for better precision than Timer
        // 200ms interval - duration display doesn't need 100ms precision
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
        timer.resume()
        durationTimer = timer
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
