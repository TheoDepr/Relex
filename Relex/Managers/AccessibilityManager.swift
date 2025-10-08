//
//  AccessibilityManager.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import Foundation
import ApplicationServices
import AppKit
import Combine

@MainActor
class AccessibilityManager: ObservableObject {
    @Published var isAccessibilityGranted = false
    @Published var lastError: String?

    private var permissionCheckTimer: Timer?

    init() {
        // Force check on main thread
        Task { @MainActor in
            checkAccessibility()
            startMonitoringPermissions()
        }
    }

    deinit {
        permissionCheckTimer?.invalidate()
    }

    func checkAccessibility() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(options)

        // Start polling for permission changes
        startMonitoringPermissions()
    }

    private func startMonitoringPermissions() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibility()
            }
        }
    }

    // MARK: - Cursor Position

    func getCursorPosition() -> CGPoint? {
        let mouseLocation = NSEvent.mouseLocation
        // Convert from Cocoa coordinates (bottom-left origin) to screen coordinates (top-left origin)
        if let screen = NSScreen.main {
            let flippedY = screen.frame.height - mouseLocation.y
            return CGPoint(x: mouseLocation.x, y: flippedY)
        }
        return nil
    }

    // MARK: - Text Capture

    func captureTextFromFocusedElement() async -> String? {
        // Force check accessibility status
        let trusted = AXIsProcessTrusted()
        print("🔍 Accessibility check - isAccessibilityGranted: \(isAccessibilityGranted), AXIsProcessTrusted: \(trusted)")

        guard trusted else {
            lastError = "Accessibility not granted"
            isAccessibilityGranted = false
            return nil
        }

        isAccessibilityGranted = true

        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            lastError = "No frontmost application"
            print("❌ No frontmost application")
            return nil
        }

        print("📱 Frontmost app: \(focusedApp.localizedName ?? "unknown")")

        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

        var focusedElement: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        print("🔍 AXUIElementCopyAttributeValue result: \(focusedResult.rawValue)")

        guard focusedResult == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            lastError = "Cannot access focused element (result: \(focusedResult.rawValue))"
            print("❌ Cannot access focused element - result: \(focusedResult.rawValue)")
            return nil
        }

        let axElement = element as! AXUIElement
        print("✅ Got focused element")

        // Try to get selected text first
        if let selectedText = getAttributeValue(axElement, attribute: kAXSelectedTextAttribute) as? String,
           !selectedText.isEmpty {
            print("📝 Got selected text: \"\(selectedText)\"")
            return selectedText
        }

        // Fall back to entire value
        if let value = getAttributeValue(axElement, attribute: kAXValueAttribute) as? String {
            print("📝 Got value: \"\(value)\"")
            return value
        }

        lastError = "No text found in focused element"
        print("❌ No text found in focused element")
        return nil
    }

    // MARK: - Text Insertion

    func insertText(_ text: String, at element: AXUIElement? = nil) async -> Bool {
        print("📝 insertText called with: \"\(text)\"")

        guard isAccessibilityGranted else {
            lastError = "Accessibility not granted"
            print("❌ Accessibility not granted")
            return false
        }

        let targetElement: AXUIElement
        if let element = element {
            targetElement = element
        } else {
            // Get focused element
            guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
                lastError = "No frontmost application"
                print("❌ No frontmost application")
                return false
            }

            print("📱 Focused app: \(focusedApp.localizedName ?? "unknown")")

            // Check if this is a web browser (they don't support AX text insertion well)
            let browserBundleIds = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
                                   "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera"]
            let isBrowser = browserBundleIds.contains(focusedApp.bundleIdentifier ?? "")

            if isBrowser {
                print("🌐 Detected web browser, using typing method")
                return simulateTyping(text)
            }

            let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
            var focusedElementRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)

            guard result == .success,
                  let focused = focusedElementRef,
                  CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                lastError = "Cannot access focused element"
                print("❌ Cannot access focused element - result: \(result.rawValue)")
                return false
            }

            targetElement = focused as! AXUIElement
            print("✅ Got focused element")
        }

        // Try to insert text via AX API (for native apps)
        print("🔧 Attempting AXUIElementSetAttributeValue...")
        let insertResult = AXUIElementSetAttributeValue(targetElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        print("🔧 AXUIElementSetAttributeValue result: \(insertResult.rawValue)")

        if insertResult == .success {
            print("✅ Text inserted via AX API")
            return true
        }

        // Fallback: simulate typing (works for most apps)
        print("⚠️ AX API failed, falling back to simulateTyping")
        return simulateTyping(text)
    }

    private func pasteUsingClipboard(_ text: String) -> Bool {
        print("📋 pasteUsingClipboard called with text length: \(text.count)")

        // Save current clipboard content as strings (not items)
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        let originalTypes = pasteboard.types ?? []
        print("📋 Original clipboard: \(originalString?.prefix(50) ?? "nil")")

        // Set text to clipboard
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        print("📋 Clipboard set success: \(success)")

        // Verify it's in clipboard
        let verifyClipboard = pasteboard.string(forType: .string)
        print("📋 Verified clipboard content: \(verifyClipboard?.prefix(50) ?? "nil")")

        // Small delay to ensure clipboard is set
        usleep(150_000) // 150ms

        // Use CGEventPost with different approach - create events with correct timing
        let source = CGEventSource(stateID: .combinedSessionState)

        // Post Cmd down
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true) else {
            print("❌ Failed to create cmdDown event")
            return false
        }
        print("📋 Posting Cmd down")
        cmdDown.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms

        // Post V down with command flag
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) else {
            print("❌ Failed to create vDown event")
            return false
        }
        vDown.flags = .maskCommand
        print("📋 Posting V down (with Cmd flag)")
        vDown.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms

        // Post V up
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            print("❌ Failed to create vUp event")
            return false
        }
        vUp.flags = .maskCommand
        print("📋 Posting V up")
        vUp.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms

        // Post Cmd up
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            print("❌ Failed to create cmdUp event")
            return false
        }
        print("📋 Posting Cmd up")
        cmdUp.post(tap: .cghidEventTap)

        // Wait for paste to complete
        usleep(300_000) // 300ms
        print("📋 Paste completed")

        // Restore original clipboard content (only if it was a simple string)
        if let originalString = originalString, originalTypes.contains(.string) {
            pasteboard.clearContents()
            pasteboard.setString(originalString, forType: .string)
            print("📋 Restored original clipboard")
        }

        return true
    }

    func simulateTyping(_ text: String) -> Bool {
        print("⌨️ simulateTyping called with text length: \(text.count)")
        // Use CGEvent to simulate keypresses - use unicode for all characters for reliability
        let source = CGEventSource(stateID: .hidSystemState)

        // Initial delay to ensure the field is ready to receive input
        usleep(200_000) // 200ms initial delay
        print("⌨️ Starting to type...")

        for char in text {
            // Use unicode posting for all characters to ensure compatibility
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                print("❌ Failed to create events for character: \(char)")
                continue
            }

            let unicodeScalar = String(char).unicodeScalars.first!.value
            var unicodeArray: [UniChar] = [UniChar(unicodeScalar)]
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeArray)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeArray)

            keyDown.post(tap: .cghidEventTap)
            usleep(10_000) // 10ms between down and up
            keyUp.post(tap: .cghidEventTap)

            // Delay between keypresses - slower to ensure all characters are captured
            usleep(30_000) // 30ms between characters
        }

        print("✅ simulateTyping completed")
        return true
    }

    // MARK: - Helpers

    private func getAttributeValue(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? (value as AnyObject) : nil
    }

    private func keyCodeForCharacter(_ character: Character) -> UInt16? {
        // Map common characters to virtual key codes
        // This is a simplified mapping; a complete one would be much larger
        let mapping: [Character: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
            "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
            "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C,
            "9": 0x19, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
            "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D,
            "m": 0x2E, " ": 0x31, ".": 0x2F, ",": 0x2B
        ]
        return mapping[Character(character.lowercased())]
    }
}
