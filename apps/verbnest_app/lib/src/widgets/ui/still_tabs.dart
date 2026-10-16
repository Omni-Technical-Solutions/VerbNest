import 'package:material_ui/material_ui.dart';

/// A tab bar with no motion, bound to the surrounding [DefaultTabController].
///
/// Material's [TabBar] slides its indicator and, when it scrolls, always
/// animates the selected tab into view (a fixed 300 ms with no switch to turn it
/// off). This one draws the same row of tabs and underline, and a change of tab
/// is simply there, with the selected tab scrolled into view at once.
///
/// [tabs] are normally [Tab] widgets. With [secondary] the indicator spans the
/// whole tab (the Material 3 secondary tab bar); otherwise it spans the label.
/// It is a [PreferredSizeWidget], so it also works as `AppBar.bottom`.
class StillTabBar extends StatefulWidget implements PreferredSizeWidget {
  const StillTabBar({
    super.key,
    required this.tabs,
    this.isScrollable = false,
    this.secondary = false,
  });

  final List<Widget> tabs;
  final bool isScrollable;
  final bool secondary;

  static const _height = 48.0;

  @override
  Size get preferredSize => const Size.fromHeight(_height + 1);

  @override
  State<StillTabBar> createState() => _StillTabBarState();
}

class _StillTabBarState extends State<StillTabBar> {
  TabController? _controller;
  late List<GlobalKey> _keys;
  int _shownIndex = -1;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.tabs.length, (_) => GlobalKey());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = DefaultTabController.of(context);
    if (!identical(c, _controller)) {
      _controller?.removeListener(_changed);
      _controller = c..addListener(_changed);
      _shownIndex = c.index;
    }
  }

  @override
  void didUpdateWidget(StillTabBar old) {
    super.didUpdateWidget(old);
    if (old.tabs.length != widget.tabs.length) {
      _keys = List.generate(widget.tabs.length, (_) => GlobalKey());
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final c = _controller!;
    if (c.index == _shownIndex || !mounted) return;
    _shownIndex = c.index;
    // Bring the selected tab into view now, in the same frame as the change
    // (all the tabs are already laid out), so the row never lags it.
    final ctx = _keys[_shownIndex].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).tabBarTheme;
    final label = (Theme.of(context).textTheme.titleSmall ?? const TextStyle())
        .merge(theme.labelStyle);
    final selectedIndex = _controller?.index ?? 0;

    Widget item(int i) {
      final selected = i == selectedIndex;
      final color = selected ? scheme.primary : scheme.onSurfaceVariant;
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DefaultTextStyle(
          style: label.copyWith(color: color),
          child: IconTheme(
            data: IconThemeData(color: color, size: 24),
            child: Center(widthFactor: 1, child: widget.tabs[i]),
          ),
        ),
      );
      final tab = Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: _keys[i],
          onTap: () => _controller!.animateTo(i),
          child: SizedBox(
            height: StillTabBar._height,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Center(
                  widthFactor: widget.isScrollable ? 1 : null,
                  child: content,
                ),
                // The underline: under the label for primary tabs, the full
                // tab for secondary ones.
                Positioned(
                  left: widget.secondary ? 0 : 16,
                  right: widget.secondary ? 0 : 16,
                  bottom: 0,
                  height: widget.secondary ? 2 : 3,
                  child: ColoredBox(
                    color: selected ? scheme.primary : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return tab;
    }

    final row = widget.isScrollable
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (var i = 0; i < widget.tabs.length; i++) item(i)],
            ),
          )
        : Row(
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                Expanded(child: item(i)),
            ],
          );
    return SizedBox(
      // The full width it is given, so a scrolling row starts at the edge.
      width: double.infinity,
      height: StillTabBar._height + 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor ?? scheme.outlineVariant,
            ),
          ),
        ),
        child: row,
      ),
    );
  }
}
