//
//  VoiceOverlayWindowManager.swift
//  Relex
//
//  Created by Theo Depraetere on 09/10/2025.
//

import AppKit
import SwiftUI

@MainActor
class VoiceOverlayWindowManager {
    private var overlayWindow: NSWindow?
    private let viewModel: VoiceOverlayViewModel
    private let audioManager: AudioRecordingManager

    init(viewModel: VoiceOverlayViewModel, audioManager: AudioRecordingManager) {
        self.viewModel = viewModel
        self.audioManager = audioManager
    }

    func showOverlay() {
        print("🪟 VoiceOverlayWindowManager: showOverlay called")

        // Close existing window if any
        overlayWindow?.close()

        // Create the SwiftUI view
        let contentView = VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)

        // Get the main screen
        guard let screen = NSScreen.main else {
            print("❌ No screen found")
            return
        }

        // Create the hosting view
        let hostingView = NSHostingView(rootView: contentView)

        // Size for the overlay (smaller for minimalistic design)
        let overlayWidth: CGFloat = 224 // 200 + padding
        let overlayHeight: CGFloat = 46 // 30 + padding

        // Position window at top center of screen
        let screenRect = screen.visibleFrame
        let windowX = screenRect.midX - (overlayWidth / 2)
        let windowY = screenRect.maxY - overlayHeight - 20 // 20px from top

        let windowFrame = NSRect(
            x: windowX,
            y: windowY,
            width: overlayWidth,
            height: overlayHeight
        )

        hostingView.frame = NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight)

        let window = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = hostingView
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false

        // Make window appear
        window.orderFrontRegardless()

        overlayWindow = window

        print("✅ Voice overlay window created and shown at (\(windowX), \(windowY))")
    }

    func hideOverlay() {
        print("🪟 VoiceOverlayWindowManager: hideOverlay called")
        overlayWindow?.close()
        overlayWindow = nil
    }

    func updatePosition() {
        // Keep window centered at top of screen
        guard let window = overlayWindow, let screen = NSScreen.main else { return }

        let screenRect = screen.visibleFrame
        let overlayWidth = window.frame.width
        let overlayHeight = window.frame.height

        let windowX = screenRect.midX - (overlayWidth / 2)
        let windowY = screenRect.maxY - overlayHeight - 20

        window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
    }
}
