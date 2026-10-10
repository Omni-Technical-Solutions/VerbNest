import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// Short coloured HTTP method label.
class MethodBadge extends StatelessWidget {
  const MethodBadge(this.method, {super.key, this.width = 40});

  final String method;
  final double width;

  static String short(String m) => switch (m.toUpperCase()) {
    'DELETE' => 'DEL',
    'OPTIONS' => 'OPT',
    final other => other.length > 5 ? other.substring(0, 5) : other,
  };

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context).method(method);
    return SizedBox(
      width: width,
      child: Text(
        short(method),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Rounded chip showing an HTTP status in its class colour.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, this.label, {super.key});

  final int status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context).status(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontFeatures: kTabularFigures,
        ),
      ),
    );
  }
}

/// Icon, title, hint and optional action for screens with nothing to show.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.titleKey,
    this.titleColor,
    this.logo = false,
  });

  /// Show the app logo above the title instead of [icon].
  final bool logo;

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  final Key? titleKey;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo)
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.lg),
                child: Image.asset(
                  'assets/logo.png',
                  width: 72,
                  height: 72,
                  errorBuilder: (_, _, _) =>
                      Icon(icon, size: 40, color: scheme.outline),
                ),
              )
            else
              Icon(icon, size: 40, color: scheme.outline),
            const SizedBox(height: Space.md),
            Text(
              title,
              key: titleKey,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: titleColor),
            ),
            if (hint != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.lg), action!],
          ],
        ),
      ),
    );
  }
}

enum BannerTone { warning, danger, info }

/// Full-width notice with an icon that eases in and out.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.tone,
    required this.child,
    this.onDismiss,
  });

  final BannerTone tone;
  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (tone) {
      BannerTone.danger => (
        s.errorContainer,
        s.onErrorContainer,
        Icons.error_outline,
      ),
      BannerTone.warning => (
        s.tertiaryContainer,
        s.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      BannerTone.info => (
        s.secondaryContainer,
        s.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Motion.base),
      curve: Motion.curve,
      // Fade only: sliding the height would move the buttons under a tap
      // that lands in the first frames.
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: Space.sm),
              Expanded(child: child),
              if (onDismiss != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: fg),
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether to show keyboard shortcut hints. Phones and tablets are driven by
/// touch, so the hints would only be noise there.
bool showsKeyboardHints(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

/// Keyboard shortcut hint such as `Ctrl+Enter`.
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key, this.color});

  final String label;

  /// Text and border colour; defaults to a muted surface tone.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final fg = color ?? s.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: color?.withValues(alpha: 0.5) ?? s.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}

/// Small pill with a count, shown on tabs that hold content.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: s.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Pulsing grey bars shown in place of content that is still loading.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.lines = 6});

  final int lines;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A repeating animation never settles, so stay still under reduced motion.
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.lines; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: FractionallySizedBox(
                  widthFactor: 0.4 + (i * 37 % 55) / 100,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.05 + 0.06 * _c.value),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
