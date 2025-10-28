<div align="center">
  <img src="content/relex_logo.png" alt="Relex Logo" width="200"/>

  # Relex

  **Open Source Voice Dictation**

  Voice dictation for macOS that works in any app - just hold Right Option, speak, and your text appears.

  💻 Fully open source • 🔒 Your data stays private • 💰 Pay only for what you use
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

#### How to Use

<img src="content/how_to_use.png" alt="How to Use" width="500"/>

Quick reference guide showing keyboard shortcuts and usage instructions.

#### Permissions

<img src="content/permissions.png" alt="Permissions" width="500"/>

Manage required permissions for accessibility and microphone access, plus configure your OpenAI API key.

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
5. Look for the **star icon** in your menu bar

### Building from Source (Optional)

If you prefer to build from source:

```bash
git clone https://github.com/TheoDepr/Relex.git
cd Relex
open Relex.xcodeproj
# Build and run with ⌘R in Xcode
```

## Detailed Setup

1. **Launch Relex**:
   - After building and running, Relex appears as a menu bar app (star icon in top-right corner)
   - Click the star icon to access Settings

2. **Grant Permissions**:
   - **Accessibility Access**: Click "Request Accessibility Access" in Settings
     - Opens System Settings → Privacy & Security → Accessibility
     - Enable Relex in the list
     - Required for hotkey monitoring and text insertion
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

## Keyboard Shortcuts

### Voice Dictation

- **Hold Right Option**: Start voice recording
- **Release Right Option**: Stop recording and transcribe
- **Escape**: Cancel recording or transcription

### Menu Bar

- **⌘,** (Command-Comma): Open Settings window
- **⌘Q** (Command-Q): Quit Relex

## Privacy & Security

Relex is designed with security and privacy as top priorities, making it safe for individual and enterprise use:

### Data Privacy
- **100% Open Source**: All code is publicly available for security audits and review
- **No Data Collection**: Relex does not collect, store, or transmit any user data, analytics, or telemetry
- **No Third-Party Tracking**: No analytics services, crash reporters, or tracking SDKs
- **Local Processing**: All audio recording happens entirely on your Mac
- **Direct API Communication**: Audio is sent directly from your machine to OpenAI's API - no intermediary servers
- **Temporary Files Only**: Audio files are created temporarily and deleted immediately after transcription

### Secure Credential Storage
- **macOS Keychain Integration**: Your OpenAI API key is stored using Apple's Keychain Services
- **Device-Only Access**: Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - keys never leave your device
- **No Cloud Sync**: API keys are not synced via iCloud or any cloud service
- **Encrypted Storage**: Leverages macOS's secure enclave for encryption

### Minimal Permissions
- **Accessibility Permission**: Only required for:
  - Monitoring Right Option and Escape key presses
  - Inserting transcribed text at cursor position
  - No screen recording or keyboard logging beyond these specific functions
- **Microphone Access**: Only active when you hold the Right Option key
  - No background recording
  - Visual indicator (overlay) always shows when microphone is active

### OpenAI API Usage
- **Your Own API Key**: You control your OpenAI account and can review all API usage
- **Direct Billing**: You pay OpenAI directly - no markup or hidden fees
- **Usage Transparency**: Built-in cost tracking shows exactly what you're spending
- **Standard OpenAI Terms**: Subject to [OpenAI's API Terms](https://openai.com/policies/terms-of-use) and [Privacy Policy](https://openai.com/policies/privacy-policy)

### Compliance & Auditing
- **Fully Auditable**: Open source codebase allows security teams to review all functionality
- **No Network Dependencies**: Only communicates with OpenAI's API - no other network requests
- **Reproducible Builds**: Build from source to verify the exact code running on your machine
- **MIT License**: Permissive licensing allows modification and internal deployment

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Credits

Built with Swift, SwiftUI, and OpenAI's GPT-4o transcription API.
