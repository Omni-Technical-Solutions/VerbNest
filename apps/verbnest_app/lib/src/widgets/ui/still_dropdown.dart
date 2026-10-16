import 'package:material_ui/material_ui.dart';

/// One choice in a [StillDropdown].
class StillEntry<T> {
  const StillEntry({required this.value, required this.label});

  final T value;
  final String label;
}

/// A drop-down choice with no motion.
///
/// Material's `DropdownMenu` opens over a fixed half second (and closes over
/// 150 ms) with no switch to turn that off. This shows the current choice in a
/// field and opens a plain menu (no transition) under it. It covers what the
/// app uses: a value, a list of entries, an optional width or full width, a text
/// style, and a borderless form for toolbars.
class StillDropdown<T> extends StatelessWidget {
  const StillDropdown({
    super.key,
    required this.entries,
    required this.onSelected,
    this.value,
    this.hintText,
    this.labelText,
    this.helperText,
    this.width,
    this.expand = false,
    this.textStyle,
    this.bordered = true,
    this.contentPadding,
  });

  final List<StillEntry<T>> entries;
  final ValueChanged<T?> onSelected;

  /// The current choice; when no entry has it, [hintText] shows instead.
  final T? value;
  final String? hintText;
  final String? labelText;
  final String? helperText;

  /// A fixed width; with [expand] the field fills the width it is given.
  final double? width;
  final bool expand;
  final TextStyle? textStyle;

  /// False for a field with no outline (the method and environment pickers in a
  /// toolbar).
  final bool bordered;
  final EdgeInsetsGeometry? contentPadding;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = topLeft & box.size;
    final picked = await showMenu<_Picked<T>>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom, rect.width, 0),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints(minWidth: rect.width),
      items: [
        for (final e in entries)
          PopupMenuItem<_Picked<T>>(
            value: _Picked(e.value),
            child: Text(
              e.label,
              style: e.value == value
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
          ),
      ],
    );
    if (picked != null) onSelected(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    StillEntry<T>? current;
    for (final e in entries) {
      if (e.value == value) {
        current = e;
        break;
      }
    }
    final text = current?.label ?? hintText ?? '';
    final style = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
        .merge(textStyle);
    final field = ConstrainedBox(
      // A touch target of at least 48 dp, whatever the padding.
      constraints: const BoxConstraints(minHeight: 48),
      child: Semantics(
        button: true,
        label: text,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(context),
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              isDense: true,
              labelText: labelText,
              helperText: helperText,
              border: bordered ? null : InputBorder.none,
              enabledBorder: bordered ? null : InputBorder.none,
              focusedBorder: bordered ? null : InputBorder.none,
              filled: bordered,
              contentPadding:
                  contentPadding ??
                  (bordered
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                      : const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        )),
              suffixIcon: Icon(
                Icons.arrow_drop_down,
                color: scheme.onSurfaceVariant,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 24,
              ),
            ),
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
    if (expand) return SizedBox(width: double.infinity, child: field);
    return width == null
        ? IntrinsicWidth(child: field)
        : SizedBox(width: width, child: field);
  }
}

/// Wraps a chosen value so that a null value can be picked (the menu returns
/// null when it is dismissed).
class _Picked<T> {
  const _Picked(this.value);

  final T? value;
}
