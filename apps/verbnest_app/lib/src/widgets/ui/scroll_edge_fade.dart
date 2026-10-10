import 'package:material_ui/material_ui.dart';

/// Fades the edge of a horizontally scrolling [child] that has more to scroll
/// to, so a clipped item reads as "more this way" and not as cut off.
///
/// The fades follow the reading direction (so they flip in right-to-left), only
/// show on a side that has hidden content, and never take touches or appear to
/// screen readers.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.width = 28,
    this.color,
  });

  final Widget child;

  /// How wide each fade is.
  final double width;

  /// The colour to fade to; the surface colour by default.
  final Color? color;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _moreBefore = false;
  bool _moreAfter = false;

  void _update(ScrollMetrics m) {
    if (m.axis != Axis.horizontal) return;
    final before = m.pixels > 1;
    final after = m.pixels < m.maxScrollExtent - 1;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
  }

  Widget _fade(BuildContext context, {required bool atStart}) {
    final color = widget.color ?? Theme.of(context).colorScheme.surface;
    return PositionedDirectional(
      key: Key(atStart ? 'fade-start' : 'fade-end'),
      start: atStart ? 0 : null,
      end: atStart ? null : 0,
      top: 0,
      bottom: 0,
      width: widget.width,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: atStart
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                end: atStart
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        _update(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _update(n.metrics);
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            if (_moreBefore) _fade(context, atStart: true),
            if (_moreAfter) _fade(context, atStart: false),
          ],
        ),
      ),
    );
  }
}
