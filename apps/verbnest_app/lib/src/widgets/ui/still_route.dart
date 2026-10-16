import 'package:material_ui/material_ui.dart';

/// A page route with no transition and no timer: the new page is simply there
/// (the theme's page transitions draw nothing either, but the stock route would
/// still run a 300 ms animation underneath).
class StillPageRoute<T> extends MaterialPageRoute<T> {
  StillPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}
