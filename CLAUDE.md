# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Relex is a system-wide AI text completion assistant for macOS with voice dictation support. It provides:
- **Text Completion**: Triggered via Option+J hotkey, captures context from the active application using Accessibility APIs, requests completions from OpenAI, and displays suggestions in a floating overlay
- **Voice Dictation**: Hold Right Option key to record, release to transcribe and insert text using OpenAI Whisper

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

**AppCoordinator** (`RelexApp.swift`):
- Central coordinator managing all managers and view models
- Sets up hotkey listeners and handles notification-based events
- Bridges between hotkey triggers and overlay display/voice recording
- Creates dependency graph for all services

**Managers**:
- **HotkeyManager**: System-wide hotkey registration using Carbon Event Manager
  - Option+J: Triggers text completion overlay
  - Right Option (hold/release): Voice recording start/stop
  - Escape: Cancel voice recording
  - Monitors key events via CGEventTap (requires Accessibility permission)
- **AccessibilityManager**: AXUIElement APIs for reading/writing text in focused applications
  - Reads text from focused UI elements
  - Inserts text via AX API or simulated typing (CGEvent)
  - Special handling for web browsers (uses typing simulation)
  - Detects cursor position
- **CompletionService**: OpenAI API integration for text completions
  - Uses gpt-4o-mini model with structured JSON output
  - Returns 3 completion options with keywords and text
  - Handles API key storage via UserDefaults
- **OverlayWindowManager**: Manages floating completion overlay window (NSPanel)
  - Creates borderless, non-activating panel positioned near cursor
  - Sets up CGEventTap to intercept overlay-specific hotkeys (Option+J/K/L, Escape)
  - Auto-refreshes completions on keystroke with 500ms debounce
- **AudioRecordingManager**: Handles audio recording for voice dictation
  - Manages microphone permissions
  - Records audio to temporary WAV files
- **TranscriptionService**: Converts audio to text via OpenAI Whisper API
- **VoiceOverlayWindowManager**: Manages voice recording overlay window

**View Models**:
- **OverlayViewModel**: State management for text completion overlay
  - Triggers completion requests
  - Handles selection navigation (Option+J/K)
  - Accepts/cancels completions (Option+L/Escape)
  - Implements debounced refresh on keystroke changes
- **VoiceOverlayViewModel**: State management for voice recording overlay

**Views**:
- **ContentView**: Main settings window with permission management and API key configuration
- **OverlayView**: SwiftUI view for completion overlay with loading/error/results states
  - Shows 3 completion options with keywords
  - Visual indication of selected option
  - Keyboard hint row
- **VoiceOverlayView**: SwiftUI view for voice recording overlay

### Key Technical Details

**Hotkey System**:
- Uses Carbon Event Manager (`RegisterEventHotKey`) for system-wide Option+J hotkey
- Uses CGEventTap for modifier key monitoring (Right Option) and overlay-specific keys
- Event notifications via NotificationCenter for loose coupling

**Text Insertion**:
- Primary: AXUIElement API (`kAXSelectedTextAttribute`)
- Fallback: CGEvent-based simulated typing character-by-character with unicode support
- Web browsers always use typing simulation for better compatibility

**Overlay Behavior**:
- Positioned below cursor with screen boundary clamping
- Non-activating panel (doesn't steal focus)
- Floating window level (appears over other windows)
- Automatic refresh on keystrokes while visible (debounced)

**Permissions Required**:
- Accessibility Access: Required for AXUIElement APIs, CGEventTap, and text insertion
- Microphone Access: Required for voice dictation feature

## Project Configuration

- **Targets**: Multi-platform (macOS 15.6, iOS 26.0, visionOS 26.0)
- **Swift Version**: 5.0
- **App Sandbox**: Disabled (`ENABLE_APP_SANDBOX = NO`) to allow Accessibility APIs
- **Bundle ID**: Relex.Relex
- **Xcode Version**: 26.0 (Swift 6 concurrency features enabled)

## Development Notes

### OpenAI Integration

CompletionService system prompt instructs the model to:
- Return exactly 3 distinct completion options
- Each option has a keyword (1-3 words) and completion text
- Never repeat input context, only provide continuation
- Keep completions under 80 tokens each
- Match tone/style of input
- Uses structured JSON output via `response_format` with strict schema validation

### Hotkey Mappings

Text Completion Overlay:
- **Option+J**: Toggle overlay / Scroll down in overlay
- **Option+K**: Scroll up in overlay
- **Option+L**: Accept selected completion
- **Escape**: Cancel and hide overlay

Voice Dictation:
- **Hold Right Option**: Start recording
- **Release Right Option**: Stop recording and transcribe
- **Escape (while recording)**: Cancel recording

### Common Gotchas

- Accessibility permission changes require app restart to take full effect
- CGEventTap requires accessibility permission and will fail silently without it
- Web browsers don't fully support AX text insertion, always use typing simulation
- Overlay uses non-activating panel to avoid stealing focus from target application
- Unicode typing simulation works more reliably than key code mapping for special characters
