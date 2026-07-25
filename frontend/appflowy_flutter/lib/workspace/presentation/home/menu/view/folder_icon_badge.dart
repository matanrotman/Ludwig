import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// [fork:folder] A folder's sidebar icon: a rounded square with a background
/// colour, the way a space's icon looks (user request 2026-07-25) — rather than
/// the bare, dimmed glyph an ordinary page row draws.
///
/// Deliberately its own small widget instead of reusing `SpaceIcon`: that one
/// reads `space_icon` / `space_icon_color` out of `View.extra`, which a folder
/// does not have, and falls back to the first letter of the name. A folder
/// always wants the folder glyph.
///
/// Sizing note: 18pt against the page row's 16pt glyph, because a filled badge
/// needs padding around its glyph to read as a badge rather than a coloured
/// square. `SpaceIcon` uses 22 in space headers, which are a taller row.
class FolderIconBadge extends StatelessWidget {
  const FolderIconBadge({super.key, this.dimension = 18.0});

  final double dimension;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6.0),
      child: Container(
        width: dimension,
        height: dimension,
        color: _badgeColor(),
        child: Center(
          child: FlowySvg(
            FlowySvgs.folder_m,
            size: const Size.square(11),
            // The glyph sits on a saturated fill, so it takes the surface
            // colour the way SpaceIcon's letter fallback does.
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    );
  }

  /// The first built-in space colour, so folders sit in the same palette as
  /// spaces without needing a colour of their own.
  ///
  /// Per-folder colours are a plausible later addition — the icon-set revamp is
  /// the natural time to decide that, so this stays one constant for now.
  Color? _badgeColor() {
    try {
      final defaultColor = builtInSpaceColors.firstOrNull;
      if (defaultColor != null) {
        return Color(int.parse(defaultColor));
      }
    } catch (error) {
      Log.error('folder: failed to parse the default badge colour: $error');
    }
    return null;
  }
}
