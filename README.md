<div align="center">
  <img src="content/relex_logo.png" alt="Relex Logo" width="200"/>

  # Relex

  **Open Source Voice Dictation**

  Voice dictation for macOS that works in any app - just hold Right Option, speak, release and your text appears.

  💻 Fully open source - 💰 Pay only for what you use
</div>

## Features

- 🌍 **Works Everywhere**: Use in any app - Chrome, Slack, Notes, Terminal, anywhere you can type
- 🎤 **Accurate Transcription**: Powered by OpenAI's GPT-4o transcription for high-quality speech-to-text
- ⚡ **Simple & Fast**: Hold Right Option to record, release to transcribe
- 🎯 **Smart Text Insertion**: Automatically inserts transcribed text at your cursor position
- 📊 **Usage Tracking**: Monitor your transcription costs and usage statistics
- 🔒 **Privacy-Focused**: Runs as a menu bar app with secure API key storage in Keychain

## Screenshots

### Menu Bar Integration

<img src="content/menubar.png" alt="Menu Bar" width="400"/>

Access Relex from the menu bar with quick access to settings and quit options.

### Voice Recording Overlay

<img src="content/overlayview.png" alt="Voice Recording Overlay" width="500"/>

The voice recording overlay appears near your cursor when you hold the Right Option key:

- Real-time waveform visualization during recording
- Pulsing dots animation during transcription
- Non-intrusive design that doesn't steal focus
- Cancellable at any time with Escape key

### Settings Window

#### Permissions

<img src="content/permissions.png" alt="Permissions" width="500"/>

Manage required permissions for accessibility and microphone access, plus configure your OpenAI API key.

#### How to Use

<img src="content/how_to_use.png" alt="How to Use" width="500"/>

Quick reference guide showing keyboard shortcuts and usage instructions.

#### Cost Tracking

<img src="content/cost_tracking.png" alt="Cost Tracking" width="500"/>

Monitor your transcription costs and usage statistics in real-time, with the ability to select different GPT-4o transcription models.

## Requirements

- macOS 15.6 or later
- Xcode 26.0 or later (for building from source)
- OpenAI API key for GPT-4o transcription
- Microphone access permission
- Accessibility access permission

## Installation

1. **Download** the latest release from [GitHub Releases](https://github.com/TheoDepr/Relex/releases)
2. **Unzip** `Relex.app.zip`
3. **Move** `Relex.app` to your Applications folder
4. **Launch** Relex (right-click and select "Open" the first time to bypass Gatekeeper)
5. Look for the **⚡ icon** in your menu bar

### Building from Source (Optional)

If you prefer to build from source:

```bash
git clone https://github.com/TheoDepr/Relex.git
cd Relex
open Relex.xcodeproj
# Build and run with ⌘R in Xcode
```

## Setup

1. **Launch Relex**:
   - After building and running, Relex appears as a menu bar app (⚡ icon in top-right corner)
   - Click the bolt icon to access Settings

2. **Grant Permissions**:
   - **Accessibility Access**: Click "Request Accessibility Access" in Settings
     - Opens System Settings → Privacy & Security → Accessibility
     - Enable Relex in the list
     - Required for system-wide hotkey monitoring and text insertion
   - **Microphone Access**: Click "Request Microphone Access" in Settings
     - Required for voice recording

3. **Configure OpenAI API Key**:
   - Click "Configure API Key" in Settings
   - Enter your OpenAI API key (get one at <https://platform.openai.com/api-keys>)
   - The key is stored securely in your system's Keychain

4. **Select Transcription Model** (Optional):
   - Choose between GPT-4o transcription models in Settings:
   - `gpt-4o-mini-transcribe`: 50% cheaper at $0.003/min
   - `gpt-4o-transcribe`: Standard quality at $0.006/min
   - `gpt-4o-transcribe-diarize`: Speaker identification at $0.006/min

## Usage

### Voice Dictation

1. **Start Recording**: Hold down the **Right Option** key
   - A floating overlay appears near your cursor with a waveform visualization
   - Speak clearly into your microphone

2. **Stop & Transcribe**: Release the **Right Option** key
   - Audio is sent to OpenAI's GPT-4o transcription API
   - Overlay shows pulsing dots during transcription
   - Transcribed text is automatically inserted at your cursor position

3. **Cancel**: Press **Escape** at any time
   - Works during recording or transcription
   - Closes overlay without inserting text

### How It Works

1. Hold Right Option → Audio recording starts with waveform visualization
2. Release Right Option → Audio is transcribed via OpenAI GPT-4o transcription API
3. Text is automatically inserted at cursor position using:
   - **Native macOS Apps**: Accessibility APIs for instant insertion
   - **Web Browsers**: Character-by-character keyboard simulation for compatibility
4. Press Escape anytime to cancel

### Usage Tracking

- View real-time statistics in Settings:
  - Total cost of API calls
  - Number of transcription requests
  - Total minutes of audio transcribed
- Reset statistics anytime using the Reset button

## Architecture

The project follows an MVVM architecture with a central coordinator pattern:

```
Relex/
├── RelexApp.swift                           # App entry point & coordinator
│   ├── AppDelegate                          # Menu bar app lifecycle
│   └── AppCoordinator                       # Central coordinator
├── Managers/
│   ├── AccessibilityManager.swift           # Text insertion via AX APIs
│   ├── AudioRecordingManager.swift          # Microphone recording
│   ├── HotkeyManager.swift                  # System-wide hotkey registration
│   ├── TranscriptionService.swift           # OpenAI Whisper API integration
│   ├── VoiceOverlayWindowManager.swift      # Voice recording overlay window
│   └── KeychainManager.swift                # Secure API key storage
├── ViewModels/
│   └── VoiceOverlayViewModel.swift          # Voice recording state management
├── Views/
│   ├── ContentView.swift                    # Settings window UI
│   └── VoiceOverlayView.swift               # Voice recording overlay UI
└── Models/
    └── UsageTracker.swift                   # API usage and cost tracking
```

### Key Components

- **AppDelegate**: Manages menu bar app with Settings and Quit menu items
- **AppCoordinator**: Coordinates voice recording workflow between managers
- **HotkeyManager**: Monitors Right Option key via CGEventTap (requires Accessibility permission)
- **AudioRecordingManager**: Records audio to temporary M4A files
- **TranscriptionService**: Converts audio to text via OpenAI GPT-4o transcription API
- **AccessibilityManager**: Inserts transcribed text using AX APIs or keyboard simulation
- **VoiceOverlayView**: Shows waveform during recording, dots during transcription

## Keyboard Shortcuts

### Voice Dictation

- **Hold Right Option**: Start voice recording
- **Release Right Option**: Stop recording and transcribe
- **Escape**: Cancel recording or transcription

### Menu Bar

- **⌘,** (Command-Comma): Open Settings window
- **⌘Q** (Command-Q): Quit Relex

## Troubleshooting

### Recording Not Starting

- **Check Accessibility Permission**: Ensure Relex is enabled in System Settings → Privacy & Security → Accessibility
- **Check Microphone Permission**: Ensure microphone access is granted
- **Try restarting the app** after granting permissions
- **Check Xcode console** for error messages if running from Xcode

### No Transcription Appearing

- **Verify API Key**: Check that your OpenAI API key is configured correctly in Settings
- **Check minimum duration**: Recordings must be at least 0.5 seconds to prevent accidental triggers
- **Check audio quality**: Ensure your microphone is working and not muted
- **Monitor usage**: Check the usage statistics to see if API calls are being made

### Text Not Inserting in Browsers

- The app uses character-by-character keyboard simulation for browsers (Chrome, Safari, Firefox)
- This is slower than AX API insertion but more compatible
- If characters are missing, file an issue with your browser version

### Overlay Not Appearing

- **Check cursor position**: Overlay appears below your cursor with screen boundary clamping
- **Check window level**: Overlay uses floating window level to appear over other windows
- **Restart the app** if the overlay doesn't show up

## API Usage & Costs

Relex uses OpenAI's GPT-4o transcription API for speech-to-text:

- **Model Options**: Select from available GPT-4o transcription models in Settings:
  - `gpt-4o-mini-transcribe`: $0.003 per minute (50% cheaper)
  - `gpt-4o-transcribe`: $0.006 per minute (standard quality)
  - `gpt-4o-transcribe-diarize`: $0.006 per minute (speaker identification)
- **Pricing**: Based on audio duration (charged per minute)
- **When Charged**: API calls are only made when you release Right Option to transcribe
- **Cost Tracking**: Real-time usage statistics available in Settings showing:
  - Total cost across all transcriptions
  - Number of API requests made
  - Total audio duration transcribed

Visit [OpenAI Pricing](https://openai.com/api/pricing/) for current rates.

## Privacy & Security

- **Local Processing**: Audio recording happens locally on your Mac
- **API Transmission**: Audio is only sent to OpenAI when you release Right Option
- **Secure Storage**: Your OpenAI API key is stored in macOS Keychain (not UserDefaults)
  - Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for maximum security
  - No iCloud sync
- **Accessibility**: Requires Accessibility permission only for:
  - System-wide hotkey monitoring (Right Option + Escape keys)
  - Text insertion at cursor position
- **No Analytics**: Relex does not collect, store, or transmit any data beyond what's sent to OpenAI's API

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Credits

Built with Swift, SwiftUI, and OpenAI's GPT-4o transcription API.
