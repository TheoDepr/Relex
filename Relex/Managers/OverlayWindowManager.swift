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
    private var runLoopSource: CFRunLoopSource?

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
    }

    func showOverlay() {
        print("🪟 OverlayWindowManager: showOverlay called")

        // Clean up old event tap first, then close window
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

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
        let overlayWidth = max(550, min(650, naturalSize.width))
        let overlayHeight = max(80, naturalSize.height + 20) // Add padding

        // Get screen bounds to ensure window stays on screen
        guard let screen = NSScreen.main else {
            print("❌ No screen found")
            return
        }
        let screenFrame = screen.visibleFrame

        // Position window below cursor with some padding
        var windowX = mouseLocation.x - overlayWidth / 2
        var windowY = mouseLocation.y - overlayHeight - 20 // 20px below cursor

        // Clamp X position to keep window on screen
        windowX = max(screenFrame.minX, min(windowX, screenFrame.maxX - overlayWidth))

        // Clamp Y position to keep window on screen
        windowY = max(screenFrame.minY, min(windowY, screenFrame.maxY - overlayHeight))

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

        // IMPORTANT: Remove event tap from run loop FIRST and ensure it's fully cleaned up
        // This ensures voice recording can work immediately after overlay is hidden
        if let source = runLoopSource {
            print("🗑️ Removing overlay event tap from run loop...")
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
            print("🗑️ Removed event tap from run loop")
        }

        if let tap = eventTap {
            print("🗑️ Disabling and invalidating overlay event tap...")
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
            print("✅ Overlay event tap fully removed - voice recording should work now")
        }

        overlayWindow?.close()
        overlayWindow = nil

        print("✅ Overlay window fully hidden and cleaned up")
    }

    private func setupEventTap() {
        // Clean up old tap if exists
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        // Only listen to keyDown events, NOT flagsChanged (to avoid interfering with voice recording)
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                let manager = Unmanaged<OverlayWindowManager>.fromOpaque(refcon).takeUnretainedValue()

                // Only process keyDown events (ignore any flagsChanged that might slip through)
                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                print("🎹 Overlay event tap - keyCode: \(keyCode), flags: \(flags)")

                // Check for Option + J (keyCode 38) to scroll down
                if flags.contains(.maskAlternate) && keyCode == 38 {
                    print("⌥J pressed - scrolling down")
                    Task { @MainActor in
                        guard !manager.viewModel.completions.isEmpty else { return }
                        let currentIndex = manager.viewModel.selectedIndex
                        let nextIndex = (currentIndex + 1) % manager.viewModel.completions.count
                        manager.viewModel.selectOption(nextIndex)
                    }
                    return nil // Consume the event
                }

                // Check for Option + K (keyCode 40) to scroll up
                if flags.contains(.maskAlternate) && keyCode == 40 {
                    print("⌥K pressed - scrolling up")
                    Task { @MainActor in
                        guard !manager.viewModel.completions.isEmpty else { return }
                        let currentIndex = manager.viewModel.selectedIndex
                        let count = manager.viewModel.completions.count
                        let prevIndex = (currentIndex - 1 + count) % count
                        manager.viewModel.selectOption(prevIndex)
                    }
                    return nil // Consume the event
                }

                // Check for Option + H (keyCode 4) to go back
                if flags.contains(.maskAlternate) && keyCode == 4 {
                    print("⌥H pressed - navigating back")
                    Task { @MainActor in
                        manager.viewModel.navigateBack()
                    }
                    return nil // Consume the event
                }

                // Check for Option + F (keyCode 3) to accept and insert
                if flags.contains(.maskAlternate) && keyCode == 3 {
                    print("⌥F pressed - accepting and inserting completion")
                    Task { @MainActor in
                        await manager.viewModel.acceptCompletion()
                    }
                    return nil // Consume the event
                }

                // Check for Shift + Option + L (keyCode 37) to accept and insert
                if flags.contains(.maskAlternate) && flags.contains(.maskShift) && keyCode == 37 {
                    print("⇧⌥L pressed - accepting and inserting completion")
                    Task { @MainActor in
                        await manager.viewModel.acceptCompletion()
                    }
                    return nil // Consume the event
                }

                // Check for Option + L (keyCode 37) to drill down
                if flags.contains(.maskAlternate) && keyCode == 37 {
                    print("⌥L pressed - drilling down into keyword")
                    Task { @MainActor in
                        await manager.viewModel.drillDownIntoKeyword()
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
                // Works at all depth levels - uses keyword context when drilling down
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

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("❌ Failed to create run loop source")
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        print("✅ Overlay event tap created and enabled (keyDown only)")
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
