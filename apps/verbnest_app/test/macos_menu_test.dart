import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/l10n/app_localizations.dart';
import 'package:verbnest_app/src/macos_menu.dart';

void main() {
  final calls = <String>[];
  MenuActions actions() => MenuActions(
    newRequest: () => calls.add('new'),
    closeTab: () => calls.add('close'),
    search: () => calls.add('search'),
    send: () => calls.add('send'),
    palette: () => calls.add('palette'),
    toggleSidebar: () => calls.add('sidebar'),
    shortcuts: () => calls.add('shortcuts'),
  );

  Future<List<PlatformMenuItem>> menus(WidgetTester t) async {
    late List<PlatformMenuItem> built;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            built = buildMacMenus(context, actions());
            return const SizedBox();
          },
        ),
      ),
    );
    return built;
  }

  List<PlatformMenuItem> flat(List<PlatformMenuItem> items) => [
    for (final i in items) ...[
      i,
      if (i is PlatformMenu) ...flat(i.menus),
      if (i is PlatformMenuItemGroup) ...flat(i.members),
    ],
  ];

  testWidgets('the menu bar has the standard top-level menus', (t) async {
    final m = await menus(t);
    expect(
      [for (final i in m) i.label],
      ['VerbNest', 'File', 'Edit', 'Request', 'View', 'Window'],
    );
  });

  testWidgets('the application and window menus keep the system items', (
    t,
  ) async {
    final all = flat(await menus(t));
    final types = [
      for (final i in all)
        if (i is PlatformProvidedMenuItem) i.type,
    ];
    expect(
      types,
      containsAll([
        PlatformProvidedMenuItemType.about,
        PlatformProvidedMenuItemType.hide,
        PlatformProvidedMenuItemType.hideOtherApplications,
        PlatformProvidedMenuItemType.showAllApplications,
        PlatformProvidedMenuItemType.quit,
        PlatformProvidedMenuItemType.toggleFullScreen,
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
      ]),
    );
  });

  testWidgets('items carry the same shortcuts as the in-app bindings', (
    t,
  ) async {
    final all = flat(await menus(t));
    PlatformMenuItem item(String label) =>
        all.firstWhere((i) => i.label == label);
    SingleActivator key(String label) =>
        item(label).shortcut! as SingleActivator;

    expect(key('New request').trigger, LogicalKeyboardKey.keyN);
    expect(key('New request').meta, isTrue);
    expect(key('Close tab').trigger, LogicalKeyboardKey.keyW);
    expect(key('Search workspace…').shift, isTrue);
    expect(key('Toggle sidebar').trigger, LogicalKeyboardKey.backslash);
    expect(key('Send request').trigger, LogicalKeyboardKey.enter);
    expect(key('Keyboard shortcuts').trigger, LogicalKeyboardKey.slash);
    expect(key('Copy').trigger, LogicalKeyboardKey.keyC);
    expect(key('Paste').trigger, LogicalKeyboardKey.keyV);
    expect(key('Redo').shift, isTrue);
  });

  testWidgets('selecting an item runs the action', (t) async {
    calls.clear();
    final all = flat(await menus(t));
    for (final label in [
      'New request',
      'Close tab',
      'Search workspace…',
      'Send request',
      'Command palette',
      'Toggle sidebar',
      'Keyboard shortcuts',
    ]) {
      all.firstWhere((i) => i.label == label).onSelected!();
    }
    expect(calls, [
      'new',
      'close',
      'search',
      'send',
      'palette',
      'sidebar',
      'shortcuts',
    ]);
  });

  testWidgets('the menu bar is only built on macOS', (t) async {
    // Elsewhere MacMenuBar returns its child unchanged.
    await t.pumpWidget(
      MaterialApp(
        home: MacMenuBar(actions: actions(), child: const Text('app')),
      ),
    );
    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(find.text('app'), findsOneWidget);
    expect(defaultTargetPlatform, isNot(TargetPlatform.macOS));
  });
}
