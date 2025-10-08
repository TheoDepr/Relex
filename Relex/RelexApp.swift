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
    @StateObject private var appCoordinator = AppCoordinator()

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
        WindowGroup {
            ContentView(
                accessibilityManager: appCoordinator.accessibilityManager,
                completionService: appCoordinator.completionService
            )
        }
        .defaultSize(width: 700, height: 650)
    }
}

@MainActor
class AppCoordinator: ObservableObject {
    let accessibilityManager = AccessibilityManager()
    let completionService = CompletionService()
    let overlayViewModel: OverlayViewModel
    let overlayWindowManager: OverlayWindowManager
    private let hotkeyManager = HotkeyManager.shared

    init() {
        // Initialize overlay view model with managers
        self.overlayViewModel = OverlayViewModel(
            accessibilityManager: accessibilityManager,
            completionService: completionService
        )

        // Initialize window manager
        self.overlayWindowManager = OverlayWindowManager(viewModel: overlayViewModel)

        // Connect view model to window manager
        self.overlayViewModel.windowManager = self.overlayWindowManager

        // Setup hotkey listener
        setupHotkeyListener()
    }

    private func setupHotkeyListener() {
        hotkeyManager.startListening()
        print("📱 AppCoordinator: Setting up hotkey listener")

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
}
