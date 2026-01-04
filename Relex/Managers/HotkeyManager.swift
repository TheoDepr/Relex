import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyID = EventHotKeyID(signature: OSType("RELX".fourCharCodeValue), id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRightOptionPressed = false
    private var isVoiceOperationActive = false // Track if recording or transcribing
    private var isMonitoringKeyDown = false // Track if we're monitoring keyDown events
    private var lastRightOptionEventTime: TimeInterval = 0
    private let debounceInterval: TimeInterval = 0.1 // 100ms debounce
    private var eventTapMonitorTimer: Timer?

    init() {
        // Start a periodic check to ensure event tap is active
        startEventTapMonitoring()

        // Monitor when app becomes active to reinitialize event tap
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Silently check if event tap needs initialization (early exits if already exists)
            self?.reinitializeEventTapIfNeeded()
        }

        // Also monitor when app finishes launching
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay slightly to ensure everything is initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.reinitializeEventTapIfNeeded()
            }
        }

        // Listen for voice operation completion to clear the active flag and reduce event tap scope
        NotificationCenter.default.addObserver(
            forName: .voiceOperationCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isVoiceOperationActive = false
            self?.switchToLightweightEventTap()
            print("✅ Voice operation completed - switched to lightweight event tap")
        }

        // Listen for voice operation cancellation to clear the active flag and reduce event tap scope
        NotificationCenter.default.addObserver(
            forName: .voiceRecordingCanceled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isVoiceOperationActive = false
            self?.switchToLightweightEventTap()
            print("🚫 Voice operation canceled - switched to lightweight event tap")
        }
    }

    func startListening() {
        print("🎯 HotkeyManager.startListening() called")

        // Check if accessibility is granted
        let hasAccessibility = AXIsProcessTrusted()
        print("🔐 Accessibility permission status in HotkeyManager: \(hasAccessibility)")

        // Start Right Option key monitoring (requires accessibility)
        if hasAccessibility {
            // Start with lightweight tap (no keyDown monitoring until voice operation starts)
            setupRightOptionMonitoring(includeKeyDown: false)
        } else {
            print("⚠️ Skipping Right Option monitoring - accessibility permission not granted")
            print("💡 Event tap will be initialized when accessibility permission is granted")
        }

        print("🎯 HotkeyManager.startListening() completed")
    }

    private func reinitializeEventTapIfNeeded() {
        // Early exit if event tap already exists - no need to check
        if eventTap != nil {
            return
        }

        // Only check accessibility if event tap is missing
        let hasAccessibility = AXIsProcessTrusted()

        // If we have accessibility but no event tap, set it up
        if hasAccessibility {
            print("🔄 Reinitializing event tap (accessibility now available)")
            // Start with lightweight tap
            setupRightOptionMonitoring(includeKeyDown: false)
        }
    }

    // Public method to force reinitialize (can be called from UI after permission granted)
    func forceReinitializeEventTap() {
        print("🔧 Force reinitializing event tap")

        // Clean up existing tap
        cleanupEventTap()

        // Try to set up again
        let hasAccessibility = AXIsProcessTrusted()
        if hasAccessibility {
            print("✅ Accessibility granted - setting up Right Option monitoring")
            // Start with lightweight tap (no keyDown monitoring)
            setupRightOptionMonitoring(includeKeyDown: false)
        } else {
            print("❌ Cannot set up event tap - accessibility permission still not granted")
        }
    }

    private func startEventTapMonitoring() {
        // Check every 10 seconds if event tap needs to be reinitialized
        // This is only needed when accessibility permission is granted after launch
        eventTapMonitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // If event tap exists, stop monitoring - no longer needed
            if self.eventTap != nil {
                print("✅ Event tap established - stopping periodic monitoring")
                self.eventTapMonitorTimer?.invalidate()
                self.eventTapMonitorTimer = nil
                return
            }

            self.reinitializeEventTapIfNeeded()
        }
    }

    /// Sets up the event tap with the specified scope
    /// - Parameter includeKeyDown: If true, monitors keyDown events for Escape key. If false, only monitors flagsChanged.
    private func setupRightOptionMonitoring(includeKeyDown: Bool = false) {
        print("🔧 Setting up Right Option monitoring (includeKeyDown: \(includeKeyDown))...")

        // Clean up existing tap if any
        cleanupEventTap()

        // Build event mask based on scope
        // Always monitor flagsChanged for Right Option key
        var eventMask = 1 << CGEventType.flagsChanged.rawValue
        
        // Only add keyDown monitoring when voice operation is active (for Escape key)
        if includeKeyDown {
            eventMask |= 1 << CGEventType.keyDown.rawValue
        }
        
        isMonitoringKeyDown = includeKeyDown
        print("🔧 Creating event tap with mask: \(eventMask) (keyDown: \(includeKeyDown))")

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let eventType = event.type

                // Handle key down events (for Escape) - only when monitoring keyDown
                if eventType == .keyDown {
                    // Escape key code is 53
                    if keyCode == 53 && manager.isVoiceOperationActive {
                        print("⎋ Escape pressed - canceling voice operation")
                        if manager.isRightOptionPressed {
                            manager.isRightOptionPressed = false
                        }
                        NotificationCenter.default.post(name: .voiceRecordingCanceled, object: nil)
                        return nil // Consume the escape key
                    }
                    return Unmanaged.passRetained(event)
                }

                // Handle flags changed events (for modifier keys)
                if eventType == .flagsChanged {
                    // Right Option key code is 61 (0x3D)
                    if keyCode == 61 {
                        // Check if the alternate flag is set (key is pressed)
                        let isPressed = flags.contains(.maskAlternate)
                        let currentTime = Date().timeIntervalSince1970

                        // Debounce rapid flag changes to prevent duplicate events
                        guard currentTime - manager.lastRightOptionEventTime >= manager.debounceInterval else {
                            return Unmanaged.passRetained(event)
                        }

                        if isPressed && !manager.isRightOptionPressed {
                            // Right Option pressed - start voice operation and enable keyDown monitoring
                            manager.isRightOptionPressed = true
                            manager.isVoiceOperationActive = true
                            manager.lastRightOptionEventTime = currentTime
                            print("🎤 Right Option key pressed (keyCode: \(keyCode))")
                            
                            // Switch to full event tap (with keyDown) for Escape key support
                            manager.switchToFullEventTap()
                            
                            NotificationCenter.default.post(name: .voiceRecordingStarted, object: nil)
                        } else if !isPressed && manager.isRightOptionPressed {
                            // Right Option released
                            manager.isRightOptionPressed = false
                            manager.lastRightOptionEventTime = currentTime
                            print("🛑 Right Option key released (keyCode: \(keyCode))")
                            NotificationCenter.default.post(name: .voiceRecordingStopped, object: nil)
                        }
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = tap else {
            print("❌ Failed to create event tap for Right Option - accessibility permission may be required")
            print("❌ Note: Event taps require accessibility permission. Make sure Relex is enabled in System Settings > Privacy & Security > Accessibility")

            // Double-check accessibility status
            let hasAccessibility = AXIsProcessTrusted()
            print("❌ Current accessibility status: \(hasAccessibility)")

            return
        }

        print("🔧 Event tap created successfully")

        // Create run loop source
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("❌ Failed to create run loop source")
            CFMachPortInvalidate(tap)
            return
        }

        print("🔧 Adding event tap to run loop")
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        print("🔧 Enabling event tap")
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        print("✅ Right Option key monitoring enabled (keyDown: \(includeKeyDown))")
    }
    
    /// Cleans up the current event tap
    private func cleanupEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }
    
    /// Switches to full event tap (flagsChanged + keyDown) for Escape key support
    private func switchToFullEventTap() {
        guard !isMonitoringKeyDown else { return } // Already monitoring keyDown
        print("🔄 Switching to full event tap (adding keyDown monitoring)")
        setupRightOptionMonitoring(includeKeyDown: true)
    }
    
    /// Switches to lightweight event tap (flagsChanged only) when voice operation ends
    private func switchToLightweightEventTap() {
        guard isMonitoringKeyDown else { return } // Already lightweight
        print("🔄 Switching to lightweight event tap (removing keyDown monitoring)")
        setupRightOptionMonitoring(includeKeyDown: false)
    }

    func stopListening() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        cleanupEventTap()

        eventTapMonitorTimer?.invalidate()
        eventTapMonitorTimer = nil

        print("Hotkey manager stopped listening")
    }

    deinit {
        stopListening()
        NotificationCenter.default.removeObserver(self)
    }
}

// Helper extension for FourCharCode conversion
extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf8 {
            result = (result << 8) | FourCharCode(char)
        }
        return result
    }
}

extension Notification.Name {
    static let voiceRecordingStarted = Notification.Name("voiceRecordingStarted")
    static let voiceRecordingStopped = Notification.Name("voiceRecordingStopped")
    static let voiceRecordingCanceled = Notification.Name("voiceRecordingCanceled")
    static let voiceOperationCompleted = Notification.Name("voiceOperationCompleted")
}
