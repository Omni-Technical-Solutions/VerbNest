import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Gives [child] at least [minHeight] and scrolls vertically when the space is
/// less. For tab bodies and forms that stack fields with an `Expanded` one:
/// large text, a landscape phone or the keyboard leave them too little room,
/// and without this they overflow instead of scrolling.
class ScrollIfShort extends StatelessWidget {
  const ScrollIfShort({super.key, this.minHeight = 280, required this.child});

  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // What a form needs grows faster than the text size: bigger text also
    // wraps onto more lines.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final needed = scale <= 1
        ? minHeight
        : minHeight * scale * math.sqrt(scale);
    return LayoutBuilder(
      builder: (context, c) => c.maxHeight >= needed
          ? child
          : SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: SizedBox(height: needed, child: child),
            ),
    );
  }
}
