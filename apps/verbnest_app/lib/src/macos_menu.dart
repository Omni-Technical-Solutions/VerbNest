import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';

/// What the menu items do; supplied by the scaffold.
class MenuActions {
  const MenuActions({
    required this.newRequest,
    required this.closeTab,
    required this.search,
    required this.send,
    required this.palette,
    required this.toggleSidebar,
    required this.shortcuts,
  });

  final VoidCallback newRequest;
  final VoidCallback closeTab;
  final VoidCallback search;
  final VoidCallback send;
  final VoidCallback palette;
  final VoidCallback toggleSidebar;
  final VoidCallback shortcuts;
}

SingleActivator _cmd(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, meta: true, shift: shift);

/// Runs [intent] on whatever has keyboard focus, like the key itself would.
void _toFocus(Intent intent) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context != null) Actions.maybeInvoke(context, intent);
}

/// The menus of the macOS menu bar, as data so they can be tested without a
/// Mac. Building a native menu bar replaces the system one, so the standard
/// application, Edit and Window items are listed here too.
List<PlatformMenuItem> buildMacMenus(BuildContext context, MenuActions a) {
  final l = context.l10n;
  return [
    _appMenu(),
    _fileMenu(l, a),
    _editMenu(l),
    _requestMenu(l, a),
    _viewMenu(l, a),
    _windowMenu(l),
  ];
}

PlatformMenu _appMenu() => PlatformMenu(
  label: 'VerbNest',
  menus: [
    const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
    PlatformMenuItemGroup(
      members: [
        if (PlatformProvidedMenuItem.hasMenu(
          PlatformProvidedMenuItemType.servicesSubmenu,
        ))
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.servicesSubmenu,
          ),
      ],
    ),
    const PlatformMenuItemGroup(
      members: [
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.hideOtherApplications,
        ),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.showAllApplications,
        ),
      ],
    ),
    const PlatformMenuItemGroup(
      members: [
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
      ],
    ),
  ],
);

PlatformMenu _fileMenu(AppLocalizations l, MenuActions a) => PlatformMenu(
  label: l.menuFile,
  menus: [
    PlatformMenuItem(
      label: l.cmdNewRequest,
      shortcut: _cmd(LogicalKeyboardKey.keyN),
      onSelected: a.newRequest,
    ),
    PlatformMenuItem(
      label: l.cmdCloseTab,
      shortcut: _cmd(LogicalKeyboardKey.keyW),
      onSelected: a.closeTab,
    ),
    PlatformMenuItem(
      label: l.cmdSearch,
      shortcut: _cmd(LogicalKeyboardKey.keyF, shift: true),
      onSelected: a.search,
    ),
  ],
);

PlatformMenu _editMenu(AppLocalizations l) => PlatformMenu(
  label: l.menuEdit,
  menus: [
    PlatformMenuItem(
      label: l.menuUndo,
      shortcut: _cmd(LogicalKeyboardKey.keyZ),
      onSelected: () =>
          _toFocus(const UndoTextIntent(SelectionChangedCause.keyboard)),
    ),
    PlatformMenuItem(
      label: l.menuRedo,
      shortcut: _cmd(LogicalKeyboardKey.keyZ, shift: true),
      onSelected: () =>
          _toFocus(const RedoTextIntent(SelectionChangedCause.keyboard)),
    ),
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: l.menuCut,
          shortcut: _cmd(LogicalKeyboardKey.keyX),
          onSelected: () => _toFocus(
            CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          ),
        ),
        PlatformMenuItem(
          label: l.copy,
          shortcut: _cmd(LogicalKeyboardKey.keyC),
          onSelected: () => _toFocus(CopySelectionTextIntent.copy),
        ),
        PlatformMenuItem(
          label: l.menuPaste,
          shortcut: _cmd(LogicalKeyboardKey.keyV),
          onSelected: () =>
              _toFocus(const PasteTextIntent(SelectionChangedCause.keyboard)),
        ),
        PlatformMenuItem(
          label: l.menuSelectAll,
          shortcut: _cmd(LogicalKeyboardKey.keyA),
          onSelected: () => _toFocus(
            const SelectAllTextIntent(SelectionChangedCause.keyboard),
          ),
        ),
      ],
    ),
  ],
);

PlatformMenu _requestMenu(AppLocalizations l, MenuActions a) => PlatformMenu(
  label: l.menuRequest,
  menus: [
    PlatformMenuItem(
      label: l.cmdSend,
      shortcut: _cmd(LogicalKeyboardKey.enter),
      onSelected: a.send,
    ),
  ],
);

PlatformMenu _viewMenu(AppLocalizations l, MenuActions a) => PlatformMenu(
  label: l.menuView,
  menus: [
    PlatformMenuItem(
      label: l.cmdToggleSidebar,
      shortcut: _cmd(LogicalKeyboardKey.backslash),
      onSelected: a.toggleSidebar,
    ),
    PlatformMenuItem(
      label: l.menuPalette,
      shortcut: _cmd(LogicalKeyboardKey.keyK),
      onSelected: a.palette,
    ),
    PlatformMenuItem(
      label: l.cmdShortcuts,
      shortcut: _cmd(LogicalKeyboardKey.slash),
      onSelected: a.shortcuts,
    ),
    const PlatformProvidedMenuItem(
      type: PlatformProvidedMenuItemType.toggleFullScreen,
    ),
  ],
);

PlatformMenu _windowMenu(AppLocalizations l) => PlatformMenu(
  label: l.menuWindow,
  menus: const [
    PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
    PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
    PlatformProvidedMenuItem(
      type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
    ),
  ],
);

/// Puts the menu bar around [child] on macOS and does nothing elsewhere.
class MacMenuBar extends StatelessWidget {
  const MacMenuBar({super.key, required this.actions, required this.child});

  final MenuActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    return PlatformMenuBar(
      menus: buildMacMenus(context, actions),
      child: child,
    );
  }
}
