import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

// Material's tooltip fades in over 150 ms and offers no switch to turn that off.
// This one is the same hint (shown after a pause on a pointer, on a long press
// on touch, read out by a screen reader) and it is simply there.

/// A hint on [child] that appears with no fade.
class StillTooltip extends StatelessWidget {
  const StillTooltip({super.key, required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return child;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RawTooltip(
      semanticsTooltip: text,
      animationStyle: AnimationStyle.noAnimation,
      hoverDelay: const Duration(milliseconds: 500),
      triggerMode: TooltipTriggerMode.longPress,
      positionDelegate: (c) => positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: 24,
        preferBelow: true,
      ),
      tooltipBuilder: (context, _) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32, maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              text,
              style: TextStyle(
                color: scheme.onInverseSurface,
                fontSize: 12,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// An icon button whose [tooltip] has no fade; otherwise Material's.
class StillIconButton extends StatelessWidget {
  const StillIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isSelected,
    this.visualDensity,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool? isSelected;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    return StillTooltip(
      message: tooltip,
      // The label goes on the button itself, as Material's tooltip does.
      child: IconButton(
        icon: tooltip == null ? icon : Semantics(label: tooltip, child: icon),
        onPressed: onPressed,
        isSelected: isSelected,
        visualDensity: visualDensity,
      ),
    );
  }
}
