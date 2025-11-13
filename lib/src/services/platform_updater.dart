import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class PlatformUpdater {
  String? _preparedScriptPath;

  /// Logs message (always, including release builds)
  void _log(String message) {
    // ignore: avoid_print
    print('[PlatformUpdater] $message');
  }

  Future<bool> installUpdate(String zipPath) async {
    try {
      _log('Starting installation: $zipPath');

      final extractPath = await _extractZip(zipPath);
      if (extractPath == null) {
        _log('Failed to extract ZIP');
        return false;
      }

      final newAppPath = await _findApp(extractPath);
      if (newAppPath == null) {
        _log('Failed to find app in extracted files');
        return false;
      }

      final scriptPath = await _createUpdateScript(newAppPath);
      if (scriptPath == null) {
        _log('Failed to create update script');
        return false;
      }

      _preparedScriptPath = scriptPath;
      _log('Update ready, waiting for user to restart');

      return true;
    } catch (e) {
      _log('Error: $e');
      return false;
    }
  }

  /// Selects extraction method based on platform
  Future<String?> _extractZip(String zipPath) async {
    // Use ditto on macOS (preserves symlinks)
    if (Platform.isMacOS) {
      return await _extractWithDitto(zipPath);
    }

    // Use archive package for Windows and Linux
    return await _extractWithArchivePackage(zipPath);
  }

  /// Extract with ditto for macOS (preserves symlinks and code signature)
  Future<String?> _extractWithDitto(String zipPath) async {
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extractPath = path.join(tempDir.path, 'StaffCo-extracted-$timestamp');

      _log('Extracting with ditto to: $extractPath');

      // Create extraction directory
      await Directory(extractPath).create(recursive: true);

      // Extract with ditto
      final result = await Process.run('ditto', [
        '-x',           // extract mode
        '-k',           // PKZip format
        zipPath,        // source ZIP
        extractPath,    // destination
      ]);

      if (result.exitCode != 0) {
        _log('Ditto error: ${result.stderr}');
        throw Exception('ditto failed: ${result.stderr}');
      }

      _log('Extraction complete with ditto');
      return extractPath;
    } catch (e) {
      _log('Ditto extract error: $e');
      return null;
    }
  }

  /// Extract with archive package for Windows and Linux
  Future<String?> _extractWithArchivePackage(String zipPath) async {
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extractPath = path.join(tempDir.path, 'StaffCo-extracted-$timestamp');

      _log('Reading ZIP file...');
      final bytes = await File(zipPath).readAsBytes();

      _log('Decoding ZIP...');
      final archive = ZipDecoder().decodeBytes(bytes);

      _log('Extracting ${archive.length} files to: $extractPath');
      final extractDir = Directory(extractPath);
      await extractDir.create(recursive: true);

      for (final file in archive) {
        final filename = path.join(extractPath, file.name);

        if (file.isFile) {
          final outFile = File(filename);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);

          if (Platform.isMacOS || Platform.isLinux) {
            try {
              await Process.run('chmod', ['+x', filename]);
            } catch (e) {
              // Ignore chmod errors for non-executables
            }
          }
        } else {
          await Directory(filename).create(recursive: true);
        }
      }

      _log('Extraction complete: $extractPath');
      return extractPath;
    } catch (e) {
      _log('Extract error: $e');
      return null;
    }
  }

  Future<String?> _findApp(String extractPath) async {
    try {
      _log('Searching for app in: $extractPath');
      final dir = Directory(extractPath);

      await for (final entity in dir.list(recursive: true)) {
        final name = path.basename(entity.path);

        if (Platform.isMacOS) {
          if (entity is Directory && name.endsWith('.app')) {
            _log('Found macOS app: ${entity.path}');
            return entity.path;
          }
        } else if (Platform.isWindows) {
          if (entity is File && name.toLowerCase().endsWith('.exe') &&
              name.toLowerCase().contains('staffco')) {
            _log('Found Windows exe: ${entity.parent.path}');
            return entity.parent.path;
          }
        } else if (Platform.isLinux) {
          if (entity is File) {
            if (name.endsWith('.AppImage') ||
                (name.toLowerCase() == 'staffco' && await _isExecutable(entity.path))) {
              _log('Found Linux binary: ${entity.parent.path}');
              return entity.parent.path;
            }
          }
        }
      }

      _log('App not found in extracted files');
      return null;
    } catch (e) {
      _log('Find app error: $e');
      return null;
    }
  }

  Future<bool> _isExecutable(String filePath) async {
    try {
      final result = await Process.run('test', ['-x', filePath]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _createUpdateScript(String newAppPath) async {
    try {
      final tempDir = Directory.systemTemp;
      final currentExe = Platform.resolvedExecutable;

      if (Platform.isMacOS) {
        final currentAppPath = _getMacOSAppPath(currentExe);
        final scriptPath = path.join(tempDir.path, 'update_helper.sh');

        bool needsSudo = false;
        if (currentAppPath.startsWith('/Applications/')) {
          try {
            final ownerResult = await Process.run('stat', ['-f', '%Su', currentAppPath]);
            final userResult = await Process.run('whoami', []);

            final owner = ownerResult.stdout.toString().trim();
            final currentUser = userResult.stdout.toString().trim();

            needsSudo = (owner != currentUser);
            _log('Path: $currentAppPath');
            _log('Owner: $owner, User: $currentUser');
            _log('Needs sudo: $needsSudo');
          } catch (e) {
            _log('Could not check ownership: $e');
          }
        }

        final script = needsSudo
            ? _createMacOSSudoScript(currentAppPath, newAppPath, scriptPath)
            : _createMacOSNormalScript(currentAppPath, newAppPath, scriptPath);

        await File(scriptPath).writeAsString(script);
        await Process.run('chmod', ['+x', scriptPath]);

        _log('Created macOS script: $scriptPath');
        return scriptPath;

      } else if (Platform.isWindows) {
        final currentDir = path.dirname(currentExe);
        final scriptPath = path.join(tempDir.path, 'update_helper.bat');

        final script = '''
@echo off
echo [Update Script] Starting update process...
timeout /t 3 /nobreak > nul

echo [Update Script] Killing current app...
taskkill /F /IM StaffCo.exe 2>nul

timeout /t 2 /nobreak > nul

echo [Update Script] Copying new files...
xcopy /E /I /Y "$newAppPath" "$currentDir"

echo [Update Script] Starting new app...
start "" "$currentExe"

echo [Update Script] Cleaning up...
del "%~f0"
''';

        await File(scriptPath).writeAsString(script);

        _log('Created Windows script: $scriptPath');
        return scriptPath;

      } else if (Platform.isLinux) {
        final currentDir = path.dirname(currentExe);
        final scriptPath = path.join(tempDir.path, 'update_helper.sh');

        final script = '''
#!/bin/bash
echo "[Update Script] Starting update process..."
sleep 3

echo "[Update Script] Killing current app..."
killall staffco StaffCo 2>/dev/null

sleep 2

echo "[Update Script] Copying new files..."
cp -rf "$newAppPath"/* "$currentDir/"

echo "[Update Script] Setting permissions..."
chmod +x "$currentExe"

sleep 1

echo "[Update Script] Starting new app..."
"$currentExe" &

echo "[Update Script] Cleaning up..."
rm -f "$scriptPath"

echo "[Update Script] Done!"
''';

        await File(scriptPath).writeAsString(script);
        await Process.run('chmod', ['+x', scriptPath]);

        _log('Created Linux script: $scriptPath');
        return scriptPath;
      }

      return null;
    } catch (e) {
      _log('Script creation error: $e');
      return null;
    }
  }

  String _getMacOSAppPath(String executablePath) {
    final parts = executablePath.split('/');
    final appIndex = parts.indexWhere((part) => part.endsWith('.app'));
    if (appIndex != -1) {
      return parts.sublist(0, appIndex + 1).join('/');
    }
    return executablePath;
  }

  String _createMacOSSudoScript(String currentAppPath, String newAppPath, String scriptPath) {
    return '''
#!/bin/bash
echo "[Update Script] Starting update with admin privileges..."

osascript -e 'do shell script "sleep 3 && killall StaffCo 2>/dev/null ; sleep 2 && rm -rf \\"$currentAppPath\\" && ditto \\"$newAppPath\\" \\"$currentAppPath\\" && chmod -R +x \\"$currentAppPath/Contents/MacOS/\\" && sleep 1 && open \\"$currentAppPath\\"" with administrator privileges'

echo "[Update Script] Cleaning up..."
rm -f "$scriptPath"

echo "[Update Script] Done!"
''';
  }

  String _createMacOSNormalScript(String currentAppPath, String newAppPath, String scriptPath) {
    return '''
#!/bin/bash
echo "[Update Script] Starting update process..."
sleep 3

echo "[Update Script] Killing current app..."
killall StaffCo staffco 2>/dev/null

sleep 2

echo "[Update Script] Removing old app: $currentAppPath"
rm -rf "$currentAppPath"

echo "[Update Script] Copying new app with ditto (preserves code signature)..."
ditto "$newAppPath" "$currentAppPath"

echo "[Update Script] Setting permissions..."
chmod -R +x "$currentAppPath/Contents/MacOS/"

sleep 1

echo "[Update Script] Opening new app..."
open "$currentAppPath"

echo "[Update Script] Cleaning up..."
rm -f "$scriptPath"

echo "[Update Script] Done!"
''';
  }

  Future<void> restartApp() async {
    _log('User clicked restart button');

    if (_preparedScriptPath == null) {
      _log('No script prepared, just exiting');
      exit(0);
      return;
    }

    _log('Launching update script: $_preparedScriptPath');

    if (Platform.isWindows) {
      await Process.start(
        'cmd',
        ['/c', _preparedScriptPath!],
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start(
        'nohup',
        ['/bin/sh', _preparedScriptPath!],
        mode: ProcessStartMode.detached,
        workingDirectory: Directory.systemTemp.path,
      );
    }

    _log('Script launched, exiting app...');
    exit(0);
  }
}