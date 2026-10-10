import 'dart:ui' show Size;

/// A phone (or foldable) size to check the layout at, with the on-screen
/// keyboard up or down. One list drives the matrix tests, so a new size is one
/// line (see docs/spec/mobile-adaptive-plan.md).
class DeviceProfile {
  const DeviceProfile(this.name, this.size, {this.keyboard = 0});

  final String name;
  final Size size;

  /// Height of the on-screen keyboard in logical pixels; 0 when it is down.
  final double keyboard;

  bool get landscape => size.width > size.height;

  DeviceProfile withKeyboard() =>
      DeviceProfile('$name+keyboard', size, keyboard: landscape ? 200 : 280);

  @override
  String toString() => name;
}

/// Phones in portrait, from a foldable's cover screen to a large phone, and
/// landscape. The keyboard variants are generated from these.
const phoneProfiles = <DeviceProfile>[
  DeviceProfile('fold-280x653', Size(280, 653)),
  DeviceProfile('se-320x568', Size(320, 568)),
  DeviceProfile('android-360x640', Size(360, 640)),
  DeviceProfile('iphone-402x874', Size(402, 874)),
  DeviceProfile('large-430x932', Size(430, 932)),
  DeviceProfile('landscape-667x375', Size(667, 375)),
  DeviceProfile('landscape-740x360', Size(740, 360)),
  DeviceProfile('landscape-874x402', Size(874, 402)),
  DeviceProfile('landscape-932x430', Size(932, 430)),
];

/// Every profile, each once without and once with the keyboard.
List<DeviceProfile> get allDeviceProfiles => [
  for (final p in phoneProfiles) ...[p, p.withKeyboard()],
];
