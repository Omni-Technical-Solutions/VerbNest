import 'package:material_ui/material_ui.dart';

// Material's switch, checkbox and chip animate when they change (the thumb
// slides, the tick draws, the chip fades its colour over 200 ms) and offer no
// switch to turn that off. These draw the same Material 3 controls and a change
// is simply there. They keep the field names of the ones they replace (`value`,
// `onChanged`, `selected`, `onSelected`), so callers and tests read the same.

/// A switch with no thumb animation.
class StillSwitch extends StatelessWidget {
  const StillSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final track = value ? scheme.primary : scheme.surfaceContainerHighest;
    final thumb = value ? scheme.onPrimary : scheme.outline;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.38,
          // 48 dp tall to touch, 52 x 32 drawn.
          child: SizedBox(
            width: 52,
            height: 48,
            child: Center(
              child: Container(
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(16),
                  border: value
                      ? null
                      : Border.all(color: scheme.outline, width: 2),
                ),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                padding: EdgeInsets.all(value ? 4 : 6),
                child: Container(
                  width: value ? 24 : 16,
                  height: value ? 24 : 16,
                  decoration: BoxDecoration(
                    color: thumb,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A list row with a [StillSwitch] at its end; the whole row toggles.
class StillSwitchListTile extends StatelessWidget {
  const StillSwitchListTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        title: title,
        subtitle: subtitle,
        trailing: StillSwitch(value: value, onChanged: onChanged),
        onTap: onChanged == null ? null : () => onChanged!(!value),
      ),
    );
  }
}

/// A checkbox with no tick animation.
class StillCheckbox extends StatelessWidget {
  const StillCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.38,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: value ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  border: value
                      ? null
                      : Border.all(color: scheme.onSurfaceVariant, width: 2),
                ),
                child: value
                    ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A list row with a [StillCheckbox] before its title; the whole row toggles.
class StillCheckboxListTile extends StatelessWidget {
  const StillCheckboxListTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final Widget title;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        dense: dense,
        leading: StillCheckbox(value: value, onChanged: onChanged),
        title: title,
        onTap: onChanged == null ? null : () => onChanged!(!value),
      ),
    );
  }
}

/// A selectable chip (the filter and choice chips) with no fade: it is filled
/// when selected, and a filter chip shows a tick.
class StillChip extends StatelessWidget {
  const StillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.showCheckmark = false,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      enabled: onSelected != null,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onSelected == null ? null : () => onSelected!(!selected),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: EdgeInsets.symmetric(
                horizontal: showCheckmark && selected ? 8 : 12,
              ),
              decoration: ShapeDecoration(
                color: selected
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                shape: StadiumBorder(
                  side: selected
                      ? BorderSide.none
                      : BorderSide(color: scheme.outline),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showCheckmark && selected) ...[
                    Icon(
                      Icons.check,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Shrinks with the room it is given, cutting a long label.
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style:
                          (Theme.of(context).textTheme.labelLarge ??
                                  const TextStyle())
                              .copyWith(
                                color: selected
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      child: label,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slider with steps and no thumb animation (Material's glides the thumb to
/// each step). Drag or tap along the track; the value snaps to a step. It reads
/// as a slider to a screen reader and moves a step with increase and decrease.
class StillSlider extends StatelessWidget {
  const StillSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;

  double _snap(double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    return min + (f * divisions).round() / divisions * (max - min);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final step = (max - min) / divisions;
    final shown = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      enabled: enabled,
      value: value.toStringAsFixed(2),
      increasedValue: (value + step).clamp(min, max).toStringAsFixed(2),
      decreasedValue: (value - step).clamp(min, max).toStringAsFixed(2),
      onIncrease: enabled
          ? () => onChanged!((value + step).clamp(min, max))
          : null,
      onDecrease: enabled
          ? () => onChanged!((value - step).clamp(min, max))
          : null,
      child: LayoutBuilder(
        builder: (context, c) {
          const pad = 12.0; // room for the thumb at each end
          final width = c.maxWidth.isFinite ? c.maxWidth : 200.0;
          double fractionAt(double dx) =>
              ((dx - pad) / (width - 2 * pad)).clamp(0.0, 1.0);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (d) => onChanged!(_snap(fractionAt(d.localPosition.dx)))
                : null,
            onHorizontalDragUpdate: enabled
                ? (d) => onChanged!(_snap(fractionAt(d.localPosition.dx)))
                : null,
            child: SizedBox(
              height: 48,
              width: width,
              child: CustomPaint(
                painter: _SliderPainter(
                  fraction: shown,
                  divisions: divisions,
                  active: enabled
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.38),
                  inactive: scheme.surfaceContainerHighest,
                  tick: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  pad: pad,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.fraction,
    required this.divisions,
    required this.active,
    required this.inactive,
    required this.tick,
    required this.pad,
  });

  final double fraction;
  final int divisions;
  final Color active;
  final Color inactive;
  final Color tick;
  final double pad;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final left = pad, right = size.width - pad;
    final x = left + (right - left) * fraction;
    final track = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawLine(Offset(left, y), Offset(right, y), track..color = inactive);
    canvas.drawLine(Offset(left, y), Offset(x, y), track..color = active);
    final dot = Paint()..color = tick;
    for (var i = 0; i <= divisions; i++) {
      final dx = left + (right - left) * i / divisions;
      if (dx > x) canvas.drawCircle(Offset(dx, y), 1.5, dot);
    }
    canvas.drawCircle(Offset(x, y), 10, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction ||
      old.active != active ||
      old.divisions != divisions;
}
