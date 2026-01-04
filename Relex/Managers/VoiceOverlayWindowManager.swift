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
        overlayWindow = nil

        // Get the main screen
        guard let screen = NSScreen.main else {
            print("❌ No screen found")
            return
        }

        // Size for the overlay
        let overlayWidth: CGFloat = 240
        let overlayHeight: CGFloat = 56

        // Position window at top center of screen
        let screenRect = screen.visibleFrame
        let windowX = screenRect.midX - (overlayWidth / 2)
        let windowY = screenRect.maxY - overlayHeight - 24

        let windowFrame = NSRect(
            x: windowX,
            y: windowY,
            width: overlayWidth,
            height: overlayHeight
        )

        // Create window first with defer: true to avoid layout recursion
        let window = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false

        // Create and set content view after window configuration
        let contentView = VoiceOverlayView(viewModel: viewModel, audioManager: audioManager)
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView

        // Store reference before showing
        overlayWindow = window

        // Make window appear
        window.orderFrontRegardless()

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
