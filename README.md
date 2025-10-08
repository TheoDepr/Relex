# Relex

An AI-powered text completion assistant for macOS that works system-wide across all applications.

## Features

- 🌍 **System-wide**: Works in any text field across all applications
- 🤖 **AI-Powered**: Uses OpenAI's GPT-4o-mini for intelligent text completions
- ⚡ **Fast**: Instant activation with keyboard shortcut
- 🎯 **Context-Aware**: Analyzes your current text to provide relevant suggestions
- 🔒 **Privacy-Focused**: Requires accessibility permissions but only accesses focused text fields

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- OpenAI API key

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd Relex
   ```

2. Open the project in Xcode:
   ```bash
   open Relex.xcodeproj
   ```

3. Build and run the project (⌘R)

## Setup

1. **Grant Accessibility Permissions**:
   - When you first launch Relex, click "Request Accessibility Access"
   - This opens System Settings → Privacy & Security → Accessibility
   - Enable Relex in the list
   - Restart the app if needed

2. **Configure OpenAI API Key**:
   - Click "Configure API Key" in the main window
   - Enter your OpenAI API key
   - The key is stored securely in your system's UserDefaults

## Usage

1. **Trigger Completion**: Press `Option + 0` in any text field
2. **Wait for Suggestion**: A floating overlay will appear with the AI-generated completion
3. **Accept**: Press `Option + [` to insert the suggestion
4. **Cancel**: Press `Escape` to dismiss

## How It Works

1. When you press `Option + 0`, Relex captures the text from your focused field
2. The text is sent to OpenAI's API for completion
3. A floating overlay appears near your cursor with the suggestion
4. Accept the suggestion to insert it into your field

### Text Insertion Methods

- **Native macOS Apps**: Uses Accessibility APIs for instant insertion
- **Web Browsers**: Simulates keyboard typing for compatibility with Chrome, Safari, Firefox, etc.

## Architecture

The project follows a modular MVVM architecture:

```
Relex/
├── Managers/
│   ├── AccessibilityManager.swift    # Text capture & insertion
│   ├── CompletionService.swift       # OpenAI API integration
│   ├── HotkeyManager.swift           # Global hotkey registration
│   └── OverlayWindowManager.swift    # Floating window management
├── Views/
│   ├── ContentView.swift             # Main settings window
│   └── OverlayView.swift             # Completion overlay UI
├── Models/
│   └── CompletionResult.swift        # Data models
└── RelexApp.swift                    # App entry point & coordinator
```

## Keyboard Shortcuts

- `Option + 0`: Trigger completion
- `Option + [`: Accept suggestion
- `Escape`: Cancel/dismiss overlay

## Troubleshooting

### Accessibility Permission Not Working
- Make sure Relex is enabled in System Settings → Privacy & Security → Accessibility
- Try restarting the app after granting permission

### No Completion Appearing
- Check that your OpenAI API key is configured correctly
- Ensure you have text in the focused field
- Check the Xcode console for error messages

### Completion Not Inserting in Browsers
- The app uses character-by-character typing for browsers
- If characters are missing, the typing may be too fast for your system
- File an issue with your browser version

## API Usage

Relex uses OpenAI's `gpt-4o-mini` model. API calls are only made when you trigger a completion with `Option + 0`.

## Privacy

- Relex only accesses text from the currently focused field when you press `Option + 0`
- Text is sent to OpenAI's API for completion
- Your API key is stored locally in UserDefaults
- No data is collected or stored by Relex

## License

[Add your license here]

## Credits

Built with Swift, SwiftUI, and OpenAI's API.
