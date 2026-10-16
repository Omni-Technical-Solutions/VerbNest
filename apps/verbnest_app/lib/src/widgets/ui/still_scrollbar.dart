import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// A scrollbar that is simply there while content scrolls: it does not fade in
/// and out (Material's fades over 300 ms and has no switch to turn that off).
/// With [thumbVisibility] it stays whenever there is something to scroll.
class StillScrollbar extends StatelessWidget {
  const StillScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.notificationPredicate,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final ScrollNotificationPredicate? notificationPredicate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RawScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      notificationPredicate:
          notificationPredicate ?? defaultScrollNotificationPredicate,
      fadeDuration: Duration.zero,
      pressDuration: Duration.zero,
      // How long it stays after the scrolling stops.
      timeToFade: const Duration(milliseconds: 700),
      thickness: 6,
      radius: const Radius.circular(Radii.sm),
      thumbColor: scheme.onSurface.withValues(alpha: 0.4),
      interactive: true,
      child: child,
    );
  }
}
