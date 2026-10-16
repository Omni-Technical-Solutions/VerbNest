import 'package:material_ui/material_ui.dart';

import '../../layout_class.dart';
import '../../theme.dart';

bool _compact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < LayoutClass.mediumBreakpoint;

/// A titled dialog that follows the window size class (Material 3): full
/// screen with a close button on a compact window, a centred dialog above.
///
/// [actions] sit in a bar at the bottom of the full-screen form and in the
/// usual place on the centred one. [width] and [height] only apply to the
/// centred form; the full-screen one uses the whole window.
class AdaptiveDialog extends StatelessWidget {
  const AdaptiveDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.width = 560,
    this.height,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (_compact(context)) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(leading: const CloseButton(), title: Text(title)),
          body: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: content,
          ),
          bottomNavigationBar: actions.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: Space.sm,
                      children: actions,
                    ),
                  ),
                ),
        ),
      );
    }
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: width, height: height, child: content),
      actions: actions,
    );
  }
}

/// A dialog without a title bar (search and the command palette): full screen
/// on a compact window, a box near the top above that.
class AdaptiveDialogShell extends StatelessWidget {
  const AdaptiveDialogShell({
    super.key,
    required this.child,
    this.width = 560,
    this.height,
    this.maxHeight,
    this.top = 80,
  });

  final Widget child;
  final double width;
  final double? height;
  final double? maxHeight;

  /// Gap above the box on a wide window.
  final double top;

  @override
  Widget build(BuildContext context) {
    if (_compact(context)) {
      return Dialog.fullscreen(child: SafeArea(child: child));
    }
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.only(top: top, left: 16, right: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: height == null
            ? child
            : SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}

/// Shows secondary detail (timings, a certificate, the variables in effect).
/// On a compact window it is a draggable bottom sheet you can swipe away, with
/// the content scrolling inside it; above that, a centred dialog with a Close
/// button.
Future<void> showDetail(
  BuildContext context, {
  required String title,
  required Widget content,
  required String closeLabel,
  double width = 360,
}) {
  if (_compact(context)) {
    return showModalBottomSheet<void>(
      sheetAnimationStyle: AnimationStyle.noAnimation,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          key: const Key('detail-sheet'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.md),
            content,
          ],
        ),
      ),
    );
  }
  return showDialog<void>(
    animationStyle: AnimationStyle.noAnimation,
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: width, child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(closeLabel),
        ),
      ],
    ),
  );
}
