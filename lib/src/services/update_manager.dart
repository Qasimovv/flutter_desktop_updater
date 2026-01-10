import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'platform_updater.dart';
import '../models/update_info.dart';
import '../config/update_config.dart';

enum UpdateStatus {
  initial,
  checking,
  updateAvailable,
  updating,
  readyToRestart,
  error
}

class UpdateManager extends ChangeNotifier {
  static final UpdateManager _instance = UpdateManager._internal();
  factory UpdateManager() => _instance;
  UpdateManager._internal();

  UpdateStatus _status = UpdateStatus.initial;
  UpdateInfo? _updateInfo;
  double _progress = 0.0;
  String? _error;
  String? _cachedZipPath;
  String? _cachedExtractPath;
  String? _preparedScriptPath;

  UpdateStatus get status => _status;
  UpdateInfo? get updateInfo => _updateInfo;
  double get progress => _progress;
  String? get error => _error;

  final _updater = PlatformUpdater();

  /// Get cache file path for storing update info
  File _getCacheFile() {
    final tempDir = Directory.systemTemp;
    final cacheDir =
        Directory(path.join(tempDir.path, 'flutter_desktop_updater'));
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return File(path.join(cacheDir.path, 'update_cache.json'));
  }

  /// Save update cache info
  void _saveCacheInfo(
      String zipPath, String extractPath, String scriptPath, UpdateInfo info) {
    try {
      final cacheFile = _getCacheFile();
      final cacheData = {
        'zipPath': zipPath,
        'extractPath': extractPath,
        'scriptPath': scriptPath,
        'version': info.version,
        'buildNumber': info.buildNumber,
        'downloadUrl': info.downloadUrl,
      };
      cacheFile.writeAsStringSync(jsonEncode(cacheData));
      _log('💾 Cached update info: version ${info.version}');
    } catch (e) {
      _log('⚠️ Failed to save cache: $e');
    }
  }

  /// Load update cache info
  Map<String, dynamic>? _loadCacheInfo() {
    try {
      final cacheFile = _getCacheFile();
      if (!cacheFile.existsSync()) return null;
      final content = cacheFile.readAsStringSync();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      _log('⚠️ Failed to load cache: $e');
      return null;
    }
  }

  /// Clear cache info
  void _clearCache() {
    try {
      final cacheFile = _getCacheFile();
      if (cacheFile.existsSync()) {
        cacheFile.deleteSync();
      }
    } catch (e) {
      _log('⚠️ Failed to clear cache: $e');
    }
  }

  /// Check if cached update files still exist and are valid
  Future<bool> _checkCachedUpdate(
      Map<String, dynamic> cacheData, UpdateInfo currentInfo) async {
    try {
      final zipPath = cacheData['zipPath'] as String?;
      final extractPath = cacheData['extractPath'] as String?;
      final scriptPath = cacheData['scriptPath'] as String?;
      final cachedVersion = cacheData['version'] as String?;
      final cachedBuildNumber = cacheData['buildNumber'] as String?;

      // Check if version matches
      if (cachedVersion != currentInfo.version ||
          cachedBuildNumber != currentInfo.buildNumber) {
        _log('🔄 Cached version mismatch, clearing cache');
        return false;
      }

      // Check if zip file exists
      if (zipPath != null) {
        final zipFile = File(zipPath);
        if (!zipFile.existsSync()) {
          _log('❌ Cached ZIP file not found');
          return false;
        }
      }

      // Check if extract path exists
      if (extractPath != null) {
        final extractDir = Directory(extractPath);
        if (!extractDir.existsSync()) {
          _log('❌ Cached extract path not found');
          return false;
        }
      }

      // Check if script path exists
      if (scriptPath != null) {
        final scriptFile = File(scriptPath);
        if (!scriptFile.existsSync()) {
          _log('❌ Cached script not found');
          return false;
        }
      }

      _log('✅ Cached update files are valid');
      return true;
    } catch (e) {
      _log('⚠️ Error checking cached update: $e');
      return false;
    }
  }

  Future<void> checkForUpdate() async {
    _log('🔍 Checking for updates...');
    _setStatus(UpdateStatus.checking);

    try {
      final updateJsonUrl = UpdateConfig().updateJsonUrl;

      final response = await http.get(Uri.parse(updateJsonUrl)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final platform = _getPlatform();

      if (!json.containsKey(platform)) {
        throw Exception('No updates for $platform');
      }

      final info = UpdateInfo.fromJson(json[platform]);
      final packageInfo = await PackageInfo.fromPlatform();

      _log('Current: ${packageInfo.version}+${packageInfo.buildNumber}');
      _log('Available: ${info.version}+${info.buildNumber}');

      if (info.isNewerThan(packageInfo.version, packageInfo.buildNumber)) {
        _updateInfo = info;

        // Check if we have a cached update for this version
        final cacheData = _loadCacheInfo();
        if (cacheData != null) {
          final isValid = await _checkCachedUpdate(cacheData, info);
          if (isValid) {
            // Restore cached paths
            _cachedZipPath = cacheData['zipPath'] as String?;
            _cachedExtractPath = cacheData['extractPath'] as String?;
            _preparedScriptPath = cacheData['scriptPath'] as String?;

            // Restore state in platform updater
            if (_preparedScriptPath != null &&
                _preparedScriptPath!.isNotEmpty) {
              _updater.setPreparedScriptPath(_preparedScriptPath);
              _log('✅ Restored cached update state, ready to restart');
            }

            _setStatus(UpdateStatus.readyToRestart);
            _log('✅ Update already downloaded and ready to install');
            return;
          } else {
            // Cache is invalid, clear it
            _clearCache();
            _cachedZipPath = null;
            _cachedExtractPath = null;
            _preparedScriptPath = null;
          }
        }

        _setStatus(UpdateStatus.updateAvailable);
        _log('✅ Update available');
      } else {
        // App is up to date, clear any old cache
        _clearCache();
        _setStatus(UpdateStatus.initial);
        _log('✅ Up to date');
      }
    } catch (e) {
      _log('❌ Check failed: $e');
      _setError('Failed to check for updates: $e');
    }
  }

  Future<void> startUpdate() async {
    if (_updateInfo == null) return;

    // Check if we already have cached update ready
    if (_status == UpdateStatus.readyToRestart && _preparedScriptPath != null) {
      _log('✅ Update already prepared, ready to restart');
      return;
    }

    _log('⬇️ Starting update...');
    _setStatus(UpdateStatus.updating);
    _progress = 0.0;

    try {
      // Use cached zip path if available, otherwise download
      String? zipPath = _cachedZipPath;
      if (zipPath == null || !File(zipPath).existsSync()) {
        zipPath = await _download();
        if (zipPath == null) throw Exception('Download failed');
        _cachedZipPath = zipPath;
      } else {
        _log('✅ Using cached ZIP file');
        _progress = 1.0;
      }

      _log('⚙️ Installing...');

      // Check if we already have extract path and script
      if (_cachedExtractPath != null &&
          _preparedScriptPath != null &&
          Directory(_cachedExtractPath!).existsSync() &&
          File(_preparedScriptPath!).existsSync()) {
        _log('✅ Using cached installation');
        // Restore script path in platform updater
        // Since we can't directly set it, we'll handle it in restartApp
      } else {
        final success = await _updater.installUpdate(zipPath);
        if (!success) throw Exception('Installation failed');

        // Get extract path and script path from platform updater
        _cachedExtractPath = _updater.extractPath;
        _preparedScriptPath = _updater.preparedScriptPath;

        // Save cache info
        if (_updateInfo != null &&
            _cachedExtractPath != null &&
            _preparedScriptPath != null) {
          _saveCacheInfo(
              zipPath, _cachedExtractPath!, _preparedScriptPath!, _updateInfo!);
        }
      }

      _log('✅ Update installed, ready to restart');
      _setStatus(UpdateStatus.readyToRestart);
    } catch (e) {
      _log('❌ Update failed: $e');
      _setError('Update failed: $e');
      // Clear cache on error
      _clearCache();
    }
  }

  Future<String?> _download() async {
    try {
      final tempDir = Directory.systemTemp;
      final savePath = '${tempDir.path}/app-update.zip';

      final request = http.Request('GET', Uri.parse(_updateInfo!.downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) return null;

      final contentLength = response.contentLength ?? 0;
      final file = File(savePath);
      final sink = file.openWrite();
      int downloaded = 0;

      await for (var chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;

        if (contentLength > 0) {
          _progress = downloaded / contentLength;
          notifyListeners();
        }
      }

      await sink.close();
      _log(
          '✅ Downloaded: ${(await file.length() / 1024 / 1024).toStringAsFixed(2)} MB');
      return savePath;
    } catch (e) {
      _log('❌ Download error: $e');
      return null;
    }
  }

  Future<void> restartApp() async {
    _log('🔄 Restarting app...');

    // If we have cached script path, restore it in platform updater
    if (_preparedScriptPath != null &&
        File(_preparedScriptPath!).existsSync()) {
      _log('Using cached script: $_preparedScriptPath');
      _updater.setPreparedScriptPath(_preparedScriptPath);
    }

    await _updater.restartApp();
  }

  void dismiss() {
    _updateInfo = null;
    _setStatus(UpdateStatus.initial);
    // Don't clear cache on dismiss, user might want to restart later
  }

  /// Clear all cached update data
  void clearCache() {
    _clearCache();
    _cachedZipPath = null;
    _cachedExtractPath = null;
    _preparedScriptPath = null;
  }

  void _setStatus(UpdateStatus status) {
    _status = status;
    _error = null;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    _status = UpdateStatus.error;
    notifyListeners();
  }

  String _getPlatform() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return '';
  }

  void _log(String msg) {
    if (kDebugMode) print('[UpdateManager] $msg');
  }
}
