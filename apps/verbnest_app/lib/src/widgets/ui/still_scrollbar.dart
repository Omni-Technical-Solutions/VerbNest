import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// A scrollbar that is simply there while content scrolls: it does not fade in
/// and out (Material's fades over 300 ms and has no switch to turn that off).
///
/// With [thumbVisibility] and a [controller] it stays whenever there is
/// something to scroll, and it is drawn in the same frame as the content (a
/// [RawScrollbar] learns the extent from a notification and so shows its thumb
/// a frame late, which reads as a flicker when a view swaps in).
class StillScrollbar extends StatelessWidget {
  const StillScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.notificationPredicate,
    this.axis = Axis.vertical,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final ScrollNotificationPredicate? notificationPredicate;

  /// The scroll direction, used by the always-shown bar.
  final Axis axis;

  static const _thickness = 6.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurface.withValues(alpha: 0.4);
    final c = controller;
    if (thumbVisibility == true && c != null) {
      return _SteadyBar(controller: c, axis: axis, color: color, child: child);
    }
    return RawScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      notificationPredicate:
          notificationPredicate ?? defaultScrollNotificationPredicate,
      fadeDuration: Duration.zero,
      pressDuration: Duration.zero,
      // How long it stays after the scrolling stops.
      timeToFade: const Duration(milliseconds: 700),
      thickness: _thickness,
      radius: const Radius.circular(Radii.sm),
      thumbColor: color,
      interactive: true,
      child: child,
    );
  }
}

/// An always-shown bar painted from the controller's position at paint time,
/// so it is right in the very frame the content is laid out. Drag the thumb to
/// scroll.
class _SteadyBar extends StatelessWidget {
  const _SteadyBar({
    required this.controller,
    required this.axis,
    required this.color,
    required this.child,
  });

  final ScrollController controller;
  final Axis axis;
  final Color color;
  final Widget child;

  static const _hit = 12.0;

  void _drag(double delta, double track) {
    if (!controller.hasClients || controller.positions.length != 1) return;
    final p = controller.position;
    if (!p.hasContentDimensions || !p.hasViewportDimension) return;
    final total = p.maxScrollExtent + p.viewportDimension;
    final thumb = (p.viewportDimension / total * track).clamp(24.0, track);
    final free = track - thumb;
    if (free <= 0) return;
    final next = (p.pixels + delta / free * p.maxScrollExtent).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    controller.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return Stack(
      children: [
        child,
        Positioned(
          left: horizontal ? 0 : null,
          right: 0,
          top: horizontal ? null : 0,
          bottom: 0,
          height: horizontal ? _hit : null,
          width: horizontal ? null : _hit,
          child: LayoutBuilder(
            builder: (context, c) {
              final track = horizontal ? c.maxWidth : c.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: horizontal
                    ? (d) => _drag(d.delta.dx, track)
                    : null,
                onVerticalDragUpdate: horizontal
                    ? null
                    : (d) => _drag(d.delta.dy, track),
                child: CustomPaint(
                  key: const Key('steady-scrollbar'),
                  size: Size.infinite,
                  painter: _ThumbPainter(controller, axis, color),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.controller, this.axis, this.color)
    : super(repaint: controller);

  final ScrollController controller;
  final Axis axis;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasClients || controller.positions.length != 1) return;
    final p = controller.position;
    if (!p.hasContentDimensions || !p.hasViewportDimension) return;
    if (p.maxScrollExtent <= 0) return;
    final horizontal = axis == Axis.horizontal;
    final track = horizontal ? size.width : size.height;
    final total = p.maxScrollExtent + p.viewportDimension;
    final thumb = (p.viewportDimension / total * track).clamp(24.0, track);
    final start =
        (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0) * (track - thumb);
    const t = StillScrollbar._thickness;
    final rect = horizontal
        ? Rect.fromLTWH(start, size.height - t - 2, thumb, t)
        : Rect.fromLTWH(size.width - t - 2, start, t, thumb);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(Radii.sm)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.controller != controller || old.axis != axis || old.color != color;
}
