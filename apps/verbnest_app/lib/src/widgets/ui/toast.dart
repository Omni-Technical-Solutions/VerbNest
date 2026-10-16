import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

enum ToastTone { info, success, error }

/// Floating message with an icon. Pass [onUndo] for reversible actions.
void showToast(
  BuildContext context,
  String message, {
  ToastTone tone = ToastTone.info,
  VoidCallback? onUndo,
  String? undoLabel,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final colors = AppColors.of(context);
  final (icon, color) = switch (tone) {
    ToastTone.success => (Icons.check_circle_outline, colors.success),
    ToastTone.error => (Icons.error_outline, colors.danger),
    ToastTone.info => (Icons.info_outline, colors.info),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      snackBarAnimationStyle: AnimationStyle.noAnimation,
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(message)),
          ],
        ),
        action: onUndo == null || undoLabel == null
            ? null
            : SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}
