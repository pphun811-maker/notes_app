import 'package:flutter/material.dart';

import '../design.dart';

/// One row of one of the app's ⋮ menus.
class AppMenuItem {
  const AppMenuItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

/// Shows one of the app's own ⋮ menus under [anchorContext].
///
/// `showMenu` on its own draws stock Material: a barely rounded surface in Material's own
/// colours, with Material's own text sizes and a surface tint that washes out the dark
/// theme's near-black. Both pages' menus went through it unchanged and looked like a piece
/// of another app sitting on top of this one. The radius, colours and text weight here are
/// the ones the list page's cards already use.
///
/// Returns the chosen item's value, or null when the menu was dismissed.
Future<String?> showAppMenu(
  BuildContext anchorContext,
  List<AppMenuItem> items,
) {
  final NotesPalette palette = NotesPalette.of(anchorContext);
  final RenderBox overlay =
      Navigator.of(anchorContext).overlay!.context.findRenderObject()!
          as RenderBox;
  final RenderBox anchor = anchorContext.findRenderObject()! as RenderBox;
  final Offset topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);

  return showMenu<String>(
    context: anchorContext,
    position: RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + anchor.size.height,
      overlay.size.width - topLeft.dx - anchor.size.width,
      0,
    ),
    color: palette.card,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NotesMetrics.cardRadius),
    ),
    items: <PopupMenuEntry<String>>[
      for (final AppMenuItem item in items)
        PopupMenuItem<String>(
          value: item.value,
          height: 52,
          child: Row(
            children: <Widget>[
              Icon(item.icon, size: 20, color: palette.sub),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: NotesType.body,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
