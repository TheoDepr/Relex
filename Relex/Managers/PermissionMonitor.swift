//
//  PermissionMonitor.swift
//  Relex
//
//  Consolidated permission monitoring for both Accessibility and Microphone permissions.
//  Reduces CPU overhead by using a single timer instead of two separate polling timers.
//

import Foundation
import AVFoundation
import ApplicationServices
import AppKit
import Combine

/// Consolidated permission monitor that checks both Accessibility and Microphone permissions
/// using a single timer, reducing CPU overhead from separate polling timers.
@MainActor
class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()
    
    @Published var isAccessibilityGranted = false
    @Published var isMicrophoneGranted = false
    
    /// True when all required permissions are granted
    var allPermissionsGranted: Bool {
        isAccessibilityGranted && isMicrophoneGranted
    }
    
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0
    
    private init() {
        // Initial check
        checkAllPermissions()
        setupAppActivationMonitoring()
        
        // Start polling if not all permissions are granted
        if !allPermissionsGranted {
            startPolling()
        }
    }
    
    deinit {
        pollingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Permission Checking
    
    func checkAllPermissions() {
        checkAccessibility()
        checkMicrophone()
        
        // Stop polling once all permissions are granted
        if allPermissionsGranted {
            stopPolling()
        }
    }
    
    private func checkAccessibility() {
        let wasGranted = isAccessibilityGranted
        isAccessibilityGranted = AXIsProcessTrusted()
        
        if isAccessibilityGranted && !wasGranted {
            print("✅ PermissionMonitor: Accessibility permission granted")
            NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
        }
    }
    
    private func checkMicrophone() {
        let wasGranted = isMicrophoneGranted
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophoneGranted = true
            if !wasGranted {
                print("✅ PermissionMonitor: Microphone permission granted")
                NotificationCenter.default.post(name: .microphonePermissionGranted, object: nil)
            }
        case .notDetermined, .denied, .restricted:
            isMicrophoneGranted = false
        @unknown default:
            isMicrophoneGranted = false
        }
    }
    
    // MARK: - Permission Requests
    
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(options)
        
        // Start polling for permission changes
        startPolling()
    }
    
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.isMicrophoneGranted = granted
                if granted {
                    print("✅ PermissionMonitor: Microphone permission granted via request")
                    NotificationCenter.default.post(name: .microphonePermissionGranted, object: nil)
                    self?.checkAllPermissions() // Check if we can stop polling
                }
            }
        }
    }
    
    // MARK: - Polling Management
    
    func startPolling() {
        // Only start if not already running and permissions not all granted
        guard pollingTimer == nil, !allPermissionsGranted else { return }
        
        print("🔄 PermissionMonitor: Starting consolidated permission polling")
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.checkAllPermissions()
            }
        }
    }
    
    func stopPolling() {
        guard pollingTimer != nil else { return }
        
        print("⏹️ PermissionMonitor: Stopping permission polling (all permissions granted)")
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - App Activation Monitoring
    
    private func setupAppActivationMonitoring() {
        // Monitor when app becomes active to immediately recheck permissions
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.checkAllPermissions()
            }
        }
        
        // Monitor when settings window opens to restart permission checking
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SettingsWindowOpened"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.startPolling()
            }
        }
        
        // Monitor when settings window closes to stop permission checking if all granted
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SettingsWindowClosed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                if self.allPermissionsGranted {
                    self.stopPolling()
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
    static let microphonePermissionGranted = Notification.Name("microphonePermissionGranted")
}

