import 'dart:io';

import 'package:verbnest_storage/verbnest_storage.dart';

/// Runs a program and returns its result. Tests replace it.
typedef RunProcess = Future<ProcessResult> Function(
  String exe,
  List<String> args,
);

/// Read-only [SecretVault] over the operating system's secret store, using
/// the tools every install already has: `security` on macOS and
/// `secret-tool` (libsecret) on Linux. It reads the entries the app wrote
/// through `flutter_secure_storage`; the CLI never writes secrets.
///
/// Windows Credential Manager has no command-line reader that returns the
/// value, so there [read] throws [UnsupportedError]; pass secrets with
/// `--var` or `VERBNEST_VAR_<name>` instead.
class SystemSecretVault implements SecretVault {
  SystemSecretVault({
    RunProcess? run,
    String? platform,
    this.service = 'flutter_secure_storage_service',
  }) : _run = run ?? ((exe, args) => Process.run(exe, args)),
       _platform = platform ?? Platform.operatingSystem;

  final RunProcess _run;
  final String _platform;

  /// The keychain service name `flutter_secure_storage` uses on macOS.
  final String service;

  /// The program and arguments that print the secret stored under [key].
  (String, List<String>) command(String key) => switch (_platform) {
    'macos' => (
      'security',
      ['find-generic-password', '-s', service, '-a', key, '-w'],
    ),
    'linux' => ('secret-tool', ['lookup', 'account', key]),
    _ => throw UnsupportedError(
      'The system secret store cannot be read from the CLI on $_platform. '
      'Use --var name=value or VERBNEST_VAR_<name> instead.',
    ),
  };

  @override
  Future<String?> read(String key) async {
    final (exe, args) = command(key);
    final ProcessResult r;
    try {
      r = await _run(exe, args);
    } on ProcessException {
      throw UnsupportedError(
        '"$exe" is not installed, so the system secret store cannot be read.',
      );
    }
    if (r.exitCode != 0) return null;
    final out = '${r.stdout}';
    // The tools end their output with a newline that is not part of the value.
    return out.endsWith('\n') ? out.substring(0, out.length - 1) : out;
  }

  @override
  Future<void> write(String key, String value) =>
      throw UnsupportedError('The CLI does not write secrets.');

  @override
  Future<void> delete(String key) =>
      throw UnsupportedError('The CLI does not write secrets.');
}
