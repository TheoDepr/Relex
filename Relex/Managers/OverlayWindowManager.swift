//
//  OverlayWindowManager.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import AppKit
import SwiftUI
import Combine

@MainActor
class OverlayWindowManager: ObservableObject {
    private var overlayWindow: NSWindow?
    private let viewModel: OverlayViewModel
    private var globalKeyMonitor: Any?
    private var eventTap: CFMachPort?

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
    }

    func showOverlay() {
        print("🪟 OverlayWindowManager: showOverlay called")

        // Close existing window if any
        overlayWindow?.close()

        // Create the SwiftUI view
        let contentView = OverlayView(viewModel: viewModel)

        // Get mouse cursor position
        let mouseLocation = NSEvent.mouseLocation

        // Verify we have a screen available
        guard NSScreen.main != nil else {
            print("❌ No screen found")
            return
        }

        // Create the hosting view and get its natural size
        let hostingView = NSHostingView(rootView: contentView)
        let naturalSize = hostingView.fittingSize

        // Size for the overlay with constraints
        let overlayWidth = max(400, min(500, naturalSize.width))
        let overlayHeight = max(80, naturalSize.height + 20) // Add padding

        // Position window below cursor with some padding
        let windowX = mouseLocation.x - overlayWidth / 2
        let windowY = mouseLocation.y - overlayHeight - 20 // 20px below cursor

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
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = hostingView
        window.isMovableByWindowBackground = true  // Allow dragging
        window.ignoresMouseEvents = false

        // Make window appear (don't use makeKeyAndOrderFront for nonactivatingPanel)
        window.orderFrontRegardless()

        overlayWindow = window

        // Setup CGEvent tap to intercept and consume Option+[ and Escape
        setupEventTap()

        print("✅ Overlay window created and shown at (\(windowX), \(windowY))")
    }

    func hideOverlay() {
        print("🪟 OverlayWindowManager: hideOverlay called")
        overlayWindow?.close()
        overlayWindow = nil

        // Disable event tap when hiding
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
            print("🗑️ Event tap removed")
        }
    }

    private func setupEventTap() {
        // Disable old tap if exists
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                let manager = Unmanaged<OverlayWindowManager>.fromOpaque(refcon).takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                print("🎹 Event tap - keyCode: \(keyCode), flags: \(flags)")

                // Check for number keys 1, 2, 3 (keyCodes 18, 19, 20) to select options
                if keyCode == 18 { // Key "1"
                    print("1️⃣ Number 1 pressed - selecting option 1")
                    Task { @MainActor in
                        manager.viewModel.selectOption(0)
                    }
                    return nil // Consume the event
                } else if keyCode == 19 { // Key "2"
                    print("2️⃣ Number 2 pressed - selecting option 2")
                    Task { @MainActor in
                        manager.viewModel.selectOption(1)
                    }
                    return nil // Consume the event
                } else if keyCode == 20 { // Key "3"
                    print("3️⃣ Number 3 pressed - selecting option 3")
                    Task { @MainActor in
                        manager.viewModel.selectOption(2)
                    }
                    return nil // Consume the event
                }

                // Check for Option + [ (keyCode 33)
                if flags.contains(.maskAlternate) && keyCode == 33 {
                    print("⌥[ pressed - accepting completion and consuming event")
                    Task { @MainActor in
                        await manager.viewModel.acceptCompletion()
                    }
                    return nil // Consume the event
                }

                // Check for Escape (keyCode 53)
                if keyCode == 53 {
                    print("⎋ Escape pressed - canceling and consuming event")
                    Task { @MainActor in
                        manager.viewModel.cancelCompletion()
                    }
                    return nil // Consume the event
                }

                // For any other keystroke while overlay is visible, refresh completion
                Task { @MainActor in
                    if manager.viewModel.isVisible && !manager.viewModel.isLoading {
                        manager.viewModel.scheduleCompletionRefresh()
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap - accessibility permission may be required")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        print("✅ Event tap created and enabled")
    }

    private func getCenterPosition() -> CGPoint {
        if let screen = NSScreen.main {
            let screenRect = screen.frame
            return CGPoint(
                x: screenRect.midX - 200,
                y: screenRect.midY - 75
            )
        }
        return CGPoint(x: 400, y: 400)
    }
}
