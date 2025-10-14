//
//  RelexApp.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import SwiftUI
import ApplicationServices
import Combine
import AppKit

@main
struct RelexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Check accessibility permissions on launch (without prompt)
        let trusted = AXIsProcessTrusted()
        print("🔐 Accessibility permission status: \(trusted)")

        if !trusted {
            print("⚠️ Accessibility permission NOT granted")
            print("👉 Please grant permission in the ContentView UI")
        } else {
            print("✅ Accessibility permission granted")
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var appCoordinator: AppCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the app coordinator
        appCoordinator = AppCoordinator()

        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Relex")
        }

        // Create menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Relex", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu

        print("📱 Menu bar app initialized")
    }

    @objc func openSettings() {
        print("📱 Opening settings window")

        if settingsWindow == nil {
            // Create settings window if it doesn't exist
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Relex Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self

            let contentView = ContentView(
                accessibilityManager: appCoordinator.accessibilityManager,
                completionService: appCoordinator.completionService,
                audioRecordingManager: appCoordinator.audioRecordingManager
            )
            window.contentView = NSHostingView(rootView: contentView)

            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        print("📱 Settings window shown")
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Keep the window instance but hide it
        print("📱 Settings window closed")
    }
}

@MainActor
class AppCoordinator: ObservableObject {
    let accessibilityManager = AccessibilityManager()
    let completionService = CompletionService()
    let overlayViewModel: OverlayViewModel
    let overlayWindowManager: OverlayWindowManager

    // Voice recording components
    let audioRecordingManager = AudioRecordingManager()
    let transcriptionService = TranscriptionService()
    let voiceOverlayViewModel: VoiceOverlayViewModel
    let voiceOverlayWindowManager: VoiceOverlayWindowManager

    private let hotkeyManager = HotkeyManager.shared

    init() {
        // Initialize text completion overlay
        self.overlayViewModel = OverlayViewModel(
            accessibilityManager: accessibilityManager,
            completionService: completionService
        )
        self.overlayWindowManager = OverlayWindowManager(viewModel: overlayViewModel)
        self.overlayViewModel.windowManager = self.overlayWindowManager

        // Initialize voice recording overlay
        self.voiceOverlayViewModel = VoiceOverlayViewModel(
            audioRecordingManager: audioRecordingManager,
            transcriptionService: transcriptionService,
            accessibilityManager: accessibilityManager
        )
        self.voiceOverlayWindowManager = VoiceOverlayWindowManager(
            viewModel: voiceOverlayViewModel,
            audioManager: audioRecordingManager
        )
        self.voiceOverlayViewModel.windowManager = self.voiceOverlayWindowManager

        // Setup hotkey listeners
        setupHotkeyListener()
        setupVoiceRecordingListener()
    }

    private func setupHotkeyListener() {
        print("📱 AppCoordinator: Setting up hotkey listener")
        hotkeyManager.startListening()
        print("📱 AppCoordinator: Hotkey manager started")

        // Listen for hotkey notifications
        NotificationCenter.default.addObserver(
            forName: .relexHotkeyTriggered,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📩 AppCoordinator: Received hotkey notification")
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleHotkeyPressed()
            }
        }
    }

    nonisolated private func handleHotkeyPressed() {
        print("🎯 AppCoordinator: Handling hotkey press")
        Task { @MainActor in
            if overlayViewModel.isVisible {
                print("👋 Hiding overlay")
                overlayViewModel.hide()
                overlayWindowManager.hideOverlay()
            } else {
                print("👀 Showing overlay and requesting completion")
                overlayViewModel.show()
                overlayWindowManager.showOverlay()
                await overlayViewModel.requestCompletion()
            }
        }
    }

    private func setupVoiceRecordingListener() {
        // Listen for voice recording start
        NotificationCenter.default.addObserver(
            forName: .voiceRecordingStarted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📩 AppCoordinator: Received voice recording started notification")
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleVoiceRecordingStarted()
            }
        }

        // Listen for voice recording stop
        NotificationCenter.default.addObserver(
            forName: .voiceRecordingStopped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📩 AppCoordinator: Received voice recording stopped notification")
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.handleVoiceRecordingStopped()
            }
        }

        // Listen for voice recording cancel
        NotificationCenter.default.addObserver(
            forName: .voiceRecordingCanceled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📩 AppCoordinator: Received voice recording canceled notification")
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleVoiceRecordingCanceled()
            }
        }
    }

    nonisolated private func handleVoiceRecordingStarted() {
        print("🎤 AppCoordinator: Handling voice recording start")
        Task { @MainActor in
            voiceOverlayWindowManager.showOverlay()
            await voiceOverlayViewModel.startRecording()
        }
    }

    nonisolated private func handleVoiceRecordingStopped() async {
        print("🛑 AppCoordinator: Handling voice recording stop")
        Task { @MainActor in
            await voiceOverlayViewModel.stopRecordingAndTranscribe()
        }
    }

    nonisolated private func handleVoiceRecordingCanceled() {
        print("🚫 AppCoordinator: Handling voice recording cancel")
        Task { @MainActor in
            voiceOverlayViewModel.cancel()
        }
    }
}
