class Version {
  final String minimum;
  final String latest;

  Version({
    required this.minimum,
    required this.latest,
  });

  factory Version.fromJson(Map<String, dynamic> json) {
    return Version(
      minimum: json['minimum'] as String,
      latest: json['latest'] as String,
    );
  }
}

class UpdateInfo {
  final Version version;
  final String buildNumber;
  final String downloadUrl;
  final int fileSize;
  final String releaseNotes;
  final bool? updateRequired;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.fileSize,
    required this.releaseNotes,
    this.updateRequired = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: Version.fromJson(json['version'] as Map<String, dynamic>),
      buildNumber: json['build_number'] as String,
      downloadUrl: json['download_url'] as String,
      fileSize: json['file_size'] as int,
      releaseNotes: json['release_notes'] as String,
      updateRequired: json['update_required'] as bool?,
    );
  }

  bool isNewerThan(String currentVersion, String currentBuildNumber) {
    final newV = version.latest.split('.').map(int.parse).toList();
    final curV = currentVersion.split('.').map(int.parse).toList();

    for (var i = 0; i < newV.length && i < curV.length; i++) {
      if (newV[i] > curV[i]) return true;
      if (newV[i] < curV[i]) return false;
    }

    if (newV.length > curV.length) return true;
    if (newV.length < curV.length) return false;

    return int.parse(buildNumber) > int.parse(currentBuildNumber);
  }
}
