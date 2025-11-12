import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class PlatformUpdater {
  String? _preparedScriptPath;

  Future<bool> installUpdate(String zipPath) async {
    try {
      print('[PlatformUpdater] Starting installation: $zipPath');

      final extractPath = await _extractZip(zipPath);
      if (extractPath == null) {
        print('[PlatformUpdater] Failed to extract ZIP');
        return false;
      }

      final newAppPath = await _findApp(extractPath);
      if (newAppPath == null) {
        print('[PlatformUpdater] Failed to find app in extracted files');
        return false;
      }

      final scriptPath = await _createUpdateScript(newAppPath);
      if (scriptPath == null) {
        print('[PlatformUpdater] Failed to create update script');
        return false;
      }

      _preparedScriptPath = scriptPath;
      print('[PlatformUpdater] Update ready, waiting for user to restart');

      return true;
    } catch (e) {
      print('[PlatformUpdater] Error: $e');
      return false;
    }
  }

  Future<String?> _extractZip(String zipPath) async {
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extractPath = path.join(tempDir.path, 'StaffCo-extracted-$timestamp');

      print('[PlatformUpdater] Reading ZIP file...');
      final bytes = await File(zipPath).readAsBytes();

      print('[PlatformUpdater] Decoding ZIP...');
      final archive = ZipDecoder().decodeBytes(bytes);

      print('[PlatformUpdater] Extracting ${archive.length} files to: $extractPath');
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

      print('[PlatformUpdater] Extraction complete: $extractPath');
      return extractPath;
    } catch (e) {
      print('[PlatformUpdater] Extract error: $e');
      return null;
    }
  }

  Future<String?> _findApp(String extractPath) async {
    try {
      print('[PlatformUpdater] Searching for app in: $extractPath');
      final dir = Directory(extractPath);

      await for (final entity in dir.list(recursive: true)) {
        final name = path.basename(entity.path);

        if (Platform.isMacOS) {
          if (entity is Directory && name.endsWith('.app')) {
            print('[PlatformUpdater] Found macOS app: ${entity.path}');
            return entity.path;
          }
        } else if (Platform.isWindows) {
          if (entity is File && name.toLowerCase().endsWith('.exe') &&
              name.toLowerCase().contains('staffco')) {
            print('[PlatformUpdater] Found Windows exe: ${entity.parent.path}');
            return entity.parent.path;
          }
        } else if (Platform.isLinux) {
          if (entity is File) {
            if (name.endsWith('.AppImage') ||
                (name.toLowerCase() == 'staffco' && await _isExecutable(entity.path))) {
              print('[PlatformUpdater] Found Linux binary: ${entity.parent.path}');
              return entity.parent.path;
            }
          }
        }
      }

      print('[PlatformUpdater] App not found in extracted files');
      return null;
    } catch (e) {
      print('[PlatformUpdater] Find app error: $e');
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
            print('[PlatformUpdater] Path: $currentAppPath');
            print('[PlatformUpdater] Owner: $owner, User: $currentUser');
            print('[PlatformUpdater] Needs sudo: $needsSudo');
          } catch (e) {
            print('[PlatformUpdater] Could not check ownership: $e');
          }
        }

        final script = needsSudo
            ? _createMacOSSudoScript(currentAppPath, newAppPath, scriptPath)
            : _createMacOSNormalScript(currentAppPath, newAppPath, scriptPath);

        await File(scriptPath).writeAsString(script);
        await Process.run('chmod', ['+x', scriptPath]);

        print('[PlatformUpdater] Created macOS script: $scriptPath');
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

        print('[PlatformUpdater] Created Windows script: $scriptPath');
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

        print('[PlatformUpdater] Created Linux script: $scriptPath');
        return scriptPath;
      }

      return null;
    } catch (e) {
      print('[PlatformUpdater] Script creation error: $e');
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

osascript -e 'do shell script "sleep 3 && killall StaffCo 2>/dev/null ; sleep 2 && rm -rf \\"$currentAppPath\\" && cp -R \\"$newAppPath\\" \\"$currentAppPath\\" && chmod -R +x \\"$currentAppPath/Contents/MacOS/\\" && sleep 1 && open \\"$currentAppPath\\"" with administrator privileges'

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

echo "[Update Script] Copying new app: $newAppPath -> $currentAppPath"
cp -R "$newAppPath" "$currentAppPath"

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
    print('[PlatformUpdater] User clicked restart button');

    if (_preparedScriptPath == null) {
      print('[PlatformUpdater] No script prepared, just exiting');
      exit(0);
      return;
    }

    print('[PlatformUpdater] Launching update script: $_preparedScriptPath');

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

    print('[PlatformUpdater] Script launched, exiting app...');
    exit(0);
  }
}