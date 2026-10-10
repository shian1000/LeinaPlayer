import 'package:flutter/material.dart';

/// Placeholder action for menu leaves that are not implemented yet.
///
/// [id] is the element's path from `docs/menu-map.md` (e.g. `Ustawienia › Konto`), so a message
/// on screen can be traced straight back to the spot in the code that needs implementing.
void showDummy(BuildContext context, String id) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Atrapa: $id'),
        duration: const Duration(seconds: 2),
      ),
    );
}
