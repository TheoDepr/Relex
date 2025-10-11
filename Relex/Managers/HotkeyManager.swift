import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyID = EventHotKeyID(signature: OSType("RELX".fourCharCodeValue), id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var eventTap: CFMachPort?
    private var isRightOptionPressed = false

    func startListening() {
        print("🎯 HotkeyManager.startListening() called")

        // Start Option+0 hotkey
        setupOptionZeroHotkey()

        // Start Right Option key monitoring
        setupRightOptionMonitoring()

        print("🎯 HotkeyManager.startListening() completed")
    }

    private func setupOptionZeroHotkey() {
        print("🔧 Setting up Option+J hotkey...")
        // Use Carbon Event Manager for system-wide hotkey registration
        // This works even in text fields because it's registered at system level
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }

            _ = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            print("🔥 Hotkey triggered: Option + J")
            NotificationCenter.default.post(name: .relexHotkeyTriggered, object: nil)

            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        if status != noErr {
            print("❌ Failed to install event handler: \(status)")
            return
        }

        // Register Option + J (keyCode 38 for 'j', optionKey modifier)
        let registerStatus = RegisterEventHotKey(
            38, // keyCode for 'j'
            UInt32(optionKey), // Option modifier
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            print("✅ Hotkey registered: Option + J (system-wide)")
        } else {
            print("❌ Failed to register hotkey: \(registerStatus)")
        }
    }

    private func setupRightOptionMonitoring() {
        print("🔧 Setting up Right Option monitoring...")

        // Disable old tap if exists
        if let tap = eventTap {
            print("🔧 Disabling existing event tap")
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        // Monitor flags changed events for modifier keys AND key down for Escape
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        print("🔧 Creating event tap with mask: \(eventMask)")

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

                // Handle key down events (for Escape)
                if eventType == .keyDown {
                    // Escape key code is 53
                    if keyCode == 53 && manager.isRightOptionPressed {
                        print("⎋ Escape pressed during recording - canceling")
                        manager.isRightOptionPressed = false
                        NotificationCenter.default.post(name: .voiceRecordingCanceled, object: nil)
                        return nil // Consume the escape key
                    }
                    return Unmanaged.passRetained(event)
                }

                // Handle flags changed events (for modifier keys)
                if eventType == .flagsChanged {
                    // Debug: Log ALL flagsChanged events to see what we're getting
                    print("🔍 FlagsChanged event - keyCode: \(keyCode), flags: \(flags.rawValue)")

                    // Right Option key code is 61 (0x3D)
                    // Left Option is 58 (0x3A) - for comparison
                    if keyCode == 61 {
                        // Check if the alternate flag is set (key is pressed)
                        let isPressed = flags.contains(.maskAlternate)

                        print("🔍 Right Option event - isPressed: \(isPressed), wasPressed: \(manager.isRightOptionPressed)")

                        if isPressed && !manager.isRightOptionPressed {
                            // Right Option pressed
                            manager.isRightOptionPressed = true
                            print("🎤 Right Option key pressed (keyCode: \(keyCode))")
                            NotificationCenter.default.post(name: .voiceRecordingStarted, object: nil)
                        } else if !isPressed && manager.isRightOptionPressed {
                            // Right Option released
                            manager.isRightOptionPressed = false
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
            return
        }

        print("🔧 Event tap created successfully")

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        print("✅ Right Option key monitoring enabled")
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

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        print("Hotkey manager stopped listening")
    }

    deinit {
        stopListening()
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
    static let relexHotkeyTriggered = Notification.Name("relexHotkeyTriggered")
    static let voiceRecordingStarted = Notification.Name("voiceRecordingStarted")
    static let voiceRecordingStopped = Notification.Name("voiceRecordingStopped")
    static let voiceRecordingCanceled = Notification.Name("voiceRecordingCanceled")
}
