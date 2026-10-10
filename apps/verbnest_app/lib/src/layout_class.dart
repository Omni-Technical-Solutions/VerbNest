/// Material 3 window size classes: compact (phones), medium (small tablets,
/// foldables), expanded (tablets, small windows), large and extra large
/// (desktop). Navigation and panes follow these (see `docs/spec/ux.md`).
enum LayoutClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static const mediumBreakpoint = 600.0;
  static const expandedBreakpoint = 840.0;
  static const largeBreakpoint = 1200.0;
  static const extraLargeBreakpoint = 1600.0;

  static LayoutClass forWidth(double width) {
    if (width >= extraLargeBreakpoint) return extraLarge;
    if (width >= largeBreakpoint) return large;
    if (width >= expandedBreakpoint) return expanded;
    if (width >= mediumBreakpoint) return medium;
    return compact;
  }

  /// True from [other] upwards, for rules such as "list and detail side by
  /// side from expanded".
  bool atLeast(LayoutClass other) => index >= other.index;
}

/// Material 3 window height classes. A landscape phone is wide but *compact*
/// in height, and needs the one-pane layout whatever its width says.
enum HeightClass {
  compact,
  medium,
  expanded;

  static const mediumBreakpoint = 480.0;
  static const expandedBreakpoint = 900.0;

  static HeightClass forHeight(double height) {
    if (height >= expandedBreakpoint) return expanded;
    if (height >= mediumBreakpoint) return medium;
    return compact;
  }

  /// True from [other] upwards.
  bool atLeast(HeightClass other) => index >= other.index;
}
