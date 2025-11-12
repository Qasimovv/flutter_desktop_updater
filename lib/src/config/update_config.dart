class UpdateConfig {
  static UpdateConfig? _instance;

  factory UpdateConfig() {
    _instance ??= UpdateConfig._internal();
    return _instance!;
  }

  UpdateConfig._internal();

  String? _updateJsonUrl;

  /// Initialize the update system with your server URL
  ///
  /// Example:
  /// ```dart
  /// UpdateConfig().configure(
  ///   updateJsonUrl: 'https://your-server.com/releases/archive.json',
  /// );
  /// ```
  void configure({required String updateJsonUrl}) {
    _updateJsonUrl = updateJsonUrl;
  }

  String get updateJsonUrl {
    if (_updateJsonUrl == null) {
      throw Exception(
          'UpdateConfig not initialized!\n'
              'Please call UpdateConfig().configure(updateJsonUrl: "...") '
              'in your main() function before using the update system.'
      );
    }
    return _updateJsonUrl!;
  }

  /// Check if config is initialized
  bool get isConfigured => _updateJsonUrl != null;
}