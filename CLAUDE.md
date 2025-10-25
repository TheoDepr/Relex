# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Relex is a system-wide voice dictation assistant for macOS. It runs as a **menu bar app** (no Dock icon) and provides:
- **Voice Dictation**: Hold Right Option key to record, release to transcribe and insert text using OpenAI Whisper
- **Menu Bar Interface**: Settings accessible via menu bar icon (⚡) in top-right corner

## Build & Run Commands

```bash
# Open the project in Xcode
open Relex.xcodeproj

# Build from command line
xcodebuild -project Relex.xcodeproj -scheme Relex -configuration Debug build

# Build for release
xcodebuild -project Relex.xcodeproj -scheme Relex -configuration Release build

# Clean build folder
xcodebuild clean -project Relex.xcodeproj -scheme Relex
```

## Architecture

The app follows an MVVM architecture with a central coordinator pattern:

### Core Components

**AppDelegate** (`RelexApp.swift`):
- Main application delegate managing the menu bar app lifecycle
- Creates and manages the menu bar status item (⚡ icon)
- Initializes the AppCoordinator and manages settings window
- Provides menu actions: Settings and Quit

**AppCoordinator** (`RelexApp.swift`):
- Central coordinator managing voice recording managers and view models
- Sets up hotkey listeners for Right Option key and handles notification-based events
- Bridges between hotkey triggers and voice recording overlay
- Creates dependency graph for voice recording services
- Initialized by AppDelegate on app launch

**Managers**:
- **HotkeyManager**: System-wide hotkey registration using CGEventTap
  - Right Option (hold/release): Voice recording start/stop
  - Escape: Cancel voice recording
  - Monitors key events via CGEventTap (requires Accessibility permission)
- **AccessibilityManager**: AXUIElement APIs for writing text in focused applications
  - Inserts text via AX API or simulated typing (CGEvent)
  - Special handling for web browsers (uses typing simulation)
- **AudioRecordingManager**: Handles audio recording for voice dictation
  - Manages microphone permissions
  - Records audio to temporary WAV files
- **TranscriptionService**: Converts audio to text via OpenAI Whisper API
  - Handles API key storage via Keychain
- **VoiceOverlayWindowManager**: Manages voice recording overlay window

**View Models**:
- **VoiceOverlayViewModel**: State management for voice recording overlay
  - Manages recording state (idle, recording, transcribing, error)
  - Coordinates between AudioRecordingManager and TranscriptionService
  - Handles text insertion after transcription

**Views**:
- **ContentView**: Settings window with permission management and API key configuration
  - Opened via menu bar Settings menu item
  - Managed as an NSWindow by AppDelegate
  - Hosts SwiftUI view with NSHostingView
  - Shows microphone and accessibility permissions
  - Manages OpenAI API key for Whisper transcription
- **VoiceOverlayView**: SwiftUI view for voice recording overlay
  - Shows waveform during recording
  - Shows pulsing dots during transcription
  - Minimal error state indicator

### Key Technical Details

**Hotkey System**:
- Uses CGEventTap for modifier key monitoring (Right Option)
- Monitors Escape key during recording for cancellation
- Event notifications via NotificationCenter for loose coupling

**Text Insertion**:
- Primary: AXUIElement API (`kAXSelectedTextAttribute`)
- Fallback: CGEvent-based simulated typing character-by-character with unicode support
- Web browsers always use typing simulation for better compatibility

**Voice Overlay Behavior**:
- Positioned below cursor with screen boundary clamping
- Non-activating panel (doesn't steal focus)
- Floating window level (appears over other windows)
- Minimal UI: waveform during recording, dots during transcription
- Cancellable at any stage (recording or transcribing) via Escape key

**Permissions Required**:
- Accessibility Access: Required for CGEventTap and text insertion
- Microphone Access: Required for voice dictation feature

## Project Configuration

- **Targets**: Multi-platform (macOS 15.6, iOS 26.0, visionOS 26.0)
- **Swift Version**: 5.0
- **App Sandbox**: Disabled (`ENABLE_APP_SANDBOX = NO`) to allow Accessibility APIs
- **Bundle ID**: Relex.Relex
- **Xcode Version**: 26.0 (Swift 6 concurrency features enabled)
- **Menu Bar App**: `INFOPLIST_KEY_LSUIElement = YES` hides Dock icon and makes app menu bar only
- **Info.plist**: Auto-generated via `GENERATE_INFOPLIST_FILE = YES` with custom keys in build settings

## Development Notes

### OpenAI Integration

TranscriptionService uses OpenAI's Whisper API for speech-to-text:
- Accepts audio files in WAV format
- Optional context parameter to improve transcription accuracy
- API key stored securely in macOS Keychain via KeychainManager
- Automatic cleanup of temporary audio files after transcription

### Keychain Storage

KeychainManager provides secure credential storage:
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for maximum security
- API keys only accessible when device is unlocked
- No iCloud sync (`kSecAttrSynchronizable = false`)
- Thread-safe implementation (no @MainActor required)
- Supports migration from legacy UserDefaults storage

### Hotkey Mappings

Voice Dictation:
- **Hold Right Option**: Start recording
- **Release Right Option**: Stop recording and transcribe
- **Escape**: Cancel recording or transcription at any time

### Menu Bar App Structure

Relex runs as a menu bar-only app (no Dock icon):
- **AppDelegate** initializes on `applicationDidFinishLaunching`
- **NSStatusItem** created with bolt.fill icon (⚡)
- **Menu items**: Settings (Cmd+,) and Quit (Cmd+Q)
- **Settings window**: Manually created NSWindow with NSHostingView wrapping SwiftUI ContentView
- **LSUIElement = YES**: Configured via `INFOPLIST_KEY_LSUIElement` in build settings to hide from Dock

### Common Gotchas

- Accessibility permission changes require app restart to take full effect
- CGEventTap requires accessibility permission and will fail silently without it
- Web browsers don't fully support AX text insertion, always use typing simulation
- Voice overlay uses non-activating panel to avoid stealing focus from target application
- Unicode typing simulation works more reliably than key code mapping for special characters
- Menu bar apps require `LSUIElement = YES` to hide Dock icon (set via build settings, not Info.plist directly)
- Minimum recording duration of 0.5 seconds prevents accidental triggers
- Transcription can be cancelled mid-process by pressing Escape
