import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyID = EventHotKeyID(signature: OSType("RELX".fourCharCodeValue), id: 1)
    private var hotKeyRef: EventHotKeyRef?

    func startListening() {
        // Use Carbon Event Manager for system-wide hotkey registration
        // This works even in text fields because it's registered at system level
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }

            _ = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            print("🔥 Hotkey triggered: Option + 0")
            NotificationCenter.default.post(name: .relexHotkeyTriggered, object: nil)

            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        if status != noErr {
            print("❌ Failed to install event handler: \(status)")
            return
        }

        // Register Option + 0 (keyCode 29 for '0', optionKey modifier)
        let registerStatus = RegisterEventHotKey(
            29, // keyCode for '0'
            UInt32(optionKey), // Option modifier
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            print("✅ Hotkey registered: Option + 0 (system-wide)")
        } else {
            print("❌ Failed to register hotkey: \(registerStatus)")
        }
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
}
