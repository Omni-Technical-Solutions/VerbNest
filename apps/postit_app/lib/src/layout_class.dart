/// Form-factor buckets from ux.md: phone, tablet, desktop.
enum LayoutClass {
  compact,
  medium,
  expanded;

  static const mediumBreakpoint = 600.0;
  static const expandedBreakpoint = 1024.0;

  static LayoutClass forWidth(double width) {
    if (width >= expandedBreakpoint) return expanded;
    if (width >= mediumBreakpoint) return medium;
    return compact;
  }
}
