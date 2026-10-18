import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version and build number, as the platform reports them
/// (the values `scripts/build.sh` passes as `--build-name` / `--build-number`).
class AppVersion {
  const AppVersion({required this.name, required this.build});

  final String name;
  final String build;

  /// `0.64.5 (47)`, or just the name when the platform gives no build number.
  String get label => build.isEmpty ? name : '$name ($build)';
}

final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(name: info.version, build: info.buildNumber);
});
