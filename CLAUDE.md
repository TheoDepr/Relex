# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Relex is a system-wide AI text completion assistant for macOS. When triggered via hotkey, it captures context from the active application using Accessibility APIs, requests completions from OpenAI, and displays suggestions in a floating SwiftUI overlay near the cursor.

**Goal**: Build a minimal working prototype that detects cursor position, extracts nearby text, sends context to OpenAI, shows suggestions in a floating window, and inserts accepted text back into the field.

## Build & Run Commands

This is an Xcode-based Swift project. Use Xcode for building and running:

```bash
# Open the project in Xcode
open Relex.xcodeproj

# Build from command line
xcodebuild -project Relex.xcodeproj -scheme Relex -configuration Debug build

# Build for release
xcodebuild -project Relex.xcodeproj -scheme Relex -configuration Release build

# Clean build folder
xcodebuild -project Relex.xcodeproj -scheme Relex clean
```

## Architecture

The app follows an MVVM architecture with modular managers:

### Core Components (to be implemented)

- **HotkeyManager**: Listens for global keyboard shortcuts to trigger the overlay
- **AccessibilityManager**: Uses AXUIElement APIs to read/write text in focused applications (requires Accessibility permissions)
- **CompletionService**: Handles async OpenAI API calls using Swift concurrency
- **OverlayViewModel**: Manages state for the floating SwiftUI overlay window

### Key Technical Requirements

- **Permissions**: The app requires Accessibility Access. Check and request via `AXIsProcessTrusted()` on launch
- **Async/Await**: Use Swift concurrency for API calls and UI updates
- **Window Management**: Overlay must be a floating, translucent NSWindow positioned near cursor
- **Text Insertion**: Use Accessibility APIs or CGEvent-based simulated typing to insert completions

## Project Configuration

- **Targets**: Multi-platform (macOS, iOS, iPadOS, visionOS)
- **macOS Deployment Target**: 15.6
- **Swift Version**: 5.0
- **App Sandbox**: Currently enabled (`ENABLE_APP_SANDBOX = YES`) - may need to be disabled or configured with specific entitlements for Accessibility and global hotkey functionality
- **Bundle ID**: Relex.Relex

## Development Notes

### Entitlements & Permissions

For the app to function, you'll likely need:
- `com.apple.security.automation.apple-events` (for accessibility)
- App Sandbox may need to be disabled or properly configured with entitlements
- Info.plist entry for `NSAppleEventsUsageDescription` explaining why accessibility is needed

### Apple HIG Compliance

- Keep UI minimal, translucent, and non-intrusive
- Use subtle animations for overlay appearance/disappearance
- Ensure proper keyboard navigation and VoiceOver support

### Error Handling

- Handle network failures gracefully (offline mode, timeouts)
- Validate Accessibility permissions before attempting to read/write text
- Provide clear user feedback when permissions are missing
