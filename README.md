# Flutter Desktop Updater

A pure Dart, cross-platform auto-update system for Flutter desktop applications.

[![pub package](https://img.shields.io/pub/v/flutter_desktop_updater.svg)](https://pub.dev/packages/flutter_desktop_updater)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

✅ **Pure Dart** - No native code required  
✅ **Cross-platform** - macOS, Windows, Linux  
✅ **Smart permissions** - Handles macOS admin rights automatically  
✅ **Progress tracking** - Real-time download progress  
✅ **User control** - Users decide when to restart  
✅ **Clean UI** - Non-intrusive banner notifications

## Screenshots

[Add screenshots here]

## Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  flutter_desktop_updater:
    git:
      url: https://github.com/qasimovv/flutter_desktop_updater.git
      ref: main
```

Or from pub.dev (once published):
```yaml
dependencies:
  flutter_desktop_updater: ^0.0.1
```

Then run:
```bash
flutter pub get
```

## Quick Start

### 1. Configure (once in main.dart)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_desktop_updater/flutter_desktop_updater.dart';

void main() {
  // Configure your update server URL
  UpdateConfig().configure(
    updateJsonUrl: 'https://your-server.com/updates/app.json',
  );
  
  runApp(const MyApp());
}
```

### 2. Check for updates
```dart
class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    // Check for updates when app starts
    UpdateManager().checkForUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Show update banner at the top
          const UpdateBanner(),
          
          // Your app content
          Expanded(
            child: YourContent(),
          ),
        ],
      ),
    );
  }
}
```

### 3. Create your update JSON file

Host a JSON file on your server with this format:
```json
{
  "macos": {
    "version": "1.0.1",
    "build_number": "2",
    "download_url": "https://your-server.com/MyApp-macos-1.0.1.zip",
    "file_size": 52428800,
    "release_notes": "Bug fixes and improvements"
  },
  "windows": {
    "version": "1.0.1",
    "build_number": "2",
    "download_url": "https://your-server.com/MyApp-windows-1.0.1.zip",
    "file_size": 48000000,
    "release_notes": "Bug fixes and improvements"
  },
  "linux": {
    "version": "1.0.1",
    "build_number": "2",
    "download_url": "https://your-server.com/MyApp-linux-1.0.1.zip",
    "file_size": 50000000,
    "release_notes": "Bug fixes and improvements"
  }
}
```

## How It Works

1. App checks for updates on startup
2. If update is available, a banner appears at the top
3. User clicks "Update" → Download starts with progress bar
4. After download completes → "Quit & Restart" button appears
5. User clicks button → App restarts with new version

## Platform-Specific Notes

### macOS
- If app is in `/Applications` and owned by root, it will request password
- **Recommended**: Install to `~/Applications` for password-free updates
- Supports both `.app` bundles

### Windows
- Works with portable `.exe` files
- No admin rights needed if installed in user folder
- **Recommended**: Use `%LOCALAPPDATA%` for installation

### Linux
- Supports both AppImage and binary formats
- No sudo needed if in user folder
- **Recommended**: Use `~/.local/bin` or `~/Applications`

## API Reference

### UpdateConfig
```dart
// Initialize (required, call once in main())
UpdateConfig().configure(
  updateJsonUrl: 'https://your-server.com/updates.json',
);

// Check if configured
bool isConfigured = UpdateConfig().isConfigured;
```

### UpdateManager
```dart
// Get singleton instance
final manager = UpdateManager();

// Check for updates
await manager.checkForUpdate();

// Start update process
await manager.startUpdate();

// Restart app
await manager.restartApp();

// Dismiss update notification
manager.dismiss();

// Listen to status changes
manager.addListener(() {
  print('Status: ${manager.status}');
  print('Progress: ${manager.progress}');
  print('Error: ${manager.error}');
});
```

### UpdateStatus
```dart
enum UpdateStatus {
  initial,          // No update check yet
  checking,         // Checking for updates
  updateAvailable,  // Update is available
  updating,         // Downloading and installing
  readyToRestart,   // Ready to restart
  error             // An error occurred
}
```

### UpdateBanner
```dart
// Simple usage (recommended)
const UpdateBanner()

// The banner automatically:
// - Shows when update is available
// - Displays download progress
// - Shows restart button when ready
// - Handles errors
```

## Example

See the [example](example/) directory for a complete working example.
```bash
cd example
flutter run -d macos  # or windows, linux
```

## Server Setup

### Option 1: GitHub Releases (Free)

1. Create a release on GitHub
2. Upload your ZIP files
3. Create `app.json` in your repo
4. Use raw GitHub URL: `https://raw.githubusercontent.com/user/repo/main/app.json`

### Option 2: Your Own Server

1. Upload ZIP files to your server
2. Create `app.json` with download URLs
3. Enable CORS if needed
4. Use HTTPS (recommended)

### Option 3: CDN (CloudFlare, AWS S3, etc.)

1. Upload files to CDN
2. Create JSON file with CDN URLs
3. Configure CDN settings

## ZIP File Structure

Your ZIP file should contain:

**macOS:**
```
MyApp-macos.zip
└── MyApp.app/
    └── Contents/
        └── MacOS/
            └── MyApp
```

**Windows:**
```
MyApp-windows.zip
└── MyApp.exe
```

**Linux:**
```
MyApp-linux.zip
└── MyApp.AppImage  (or binary)
```

## Troubleshooting

### macOS: "App is damaged"
```bash
# Remove quarantine attribute
xattr -cr /Applications/MyApp.app
```

### Windows: Antivirus blocking
- Add exception to Windows Defender
- Code sign your app (recommended)

### Linux: Permission denied
```bash
# Make executable
chmod +x MyApp.AppImage
```

## Contributing

Contributions are welcome! Please read our [contributing guidelines](CONTRIBUTING.md) first.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- 📫 [GitHub Issues](https://github.com/qasimovv/flutter_desktop_updater/issues)
- 📖 [Documentation](https://github.com/qasimovv/flutter_desktop_updater/wiki)
- 💬 [Discussions](https://github.com/qasimovv/flutter_desktop_updater/discussions)

## Author

[Your Name](https://github.com/qasimovv)