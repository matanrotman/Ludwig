// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 5).
//
// Per-page background colour for the page sheet.
//
// Stored in `View.extra` per page, exactly like the per-page text direction and
// per-page theme (page_theme_mode.dart / page_text_direction.dart): [absence of
// the key] = inherit the theme's default surface, so untouched pages render
// byte-identically to before.
//
// The stored value is one of:
//   * a FlowyTint id ('appflowy_them_color_tint3') — a THEME-AWARE preset that
//     re-resolves per theme, so a coloured page that is later flipped to dark
//     (via the ribbon's per-page theme toggle) adapts instead of clashing. This
//     is why the colour is resolved inside PageSurface, which builds under
//     PageThemeScope, rather than resolved by the caller.
//   * a custom ARGB hex ('0xFFAABBCC') — a fixed colour, the "exact colour" path.
//
// Only the sheet is tinted; the desk behind it keeps auto-deriving a recessed
// shade from the sheet (page_surface.dart), so the "sheet on a desk" depth
// survives the colour change.

import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/color_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/extensions/flowy_tint_extension.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
// `tryToColor` (String ext) and `AppFlowyEditorL10n` come from here; the editor
// also exports a `CustomColorItem`, so hide it in favour of the desktop
// toolbar's — the one whose (colorController, opacityController) API we use.
import 'package:appflowy_editor/appflowy_editor.dart' hide CustomColorItem;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'ribbon_button.dart';

/// Key under which the page's own background colour lives inside `View.extra`.
/// Namespaced because `extra` is a shared JSON blob.
const String kPageColorExtKey = 'page_color';

/// The colour a stored id resolves to for the CURRENT theme in [context], or
/// null when the page inherits (no colour, or an unparseable value).
///
/// Must be called under the page's theme (PageThemeScope) for a tint to pick up
/// a per-page light/dark override.
Color? resolvePageSheetColor(String? id, BuildContext context) {
  if (id == null || id.isEmpty) {
    return null;
  }
  final tint = FlowyTint.fromId(id);
  if (tint != null) {
    return tint.color(context);
  }
  return id.tryToColor();
}

extension PageColorViewExtension on ViewPB {
  /// This page's stored colour id, or null when unset. Falls back rather than
  /// throwing on a non-document layout or unparseable `extra`, matching the
  /// other `View.extra` getters.
  String? get pageColorId {
    if (layout != ViewLayoutPB.Document) {
      return null;
    }
    try {
      if (extra.isEmpty) {
        return null;
      }
      final ext = jsonDecode(extra);
      if (ext is! Map) {
        return null;
      }
      final value = ext[kPageColorExtKey];
      return value is String && value.isNotEmpty ? value : null;
    } catch (e) {
      Log.warn('failed to read page color from view $id: $e');
      return null;
    }
  }
}

/// Persists [colorId] onto [view], preserving every other key in `extra`. A null
/// [colorId] clears the override, returning the page to the theme default.
///
/// Reads the latest `extra` from the backend before the read-modify-write, like
/// `setPageThemeMode`.
Future<void> setPageColor(ViewPB view, String? colorId) async {
  if (view.id.isEmpty) {
    return;
  }

  Map<String, dynamic> current = {};
  final latest = await ViewBackendService.getView(view.id);
  latest.fold(
    (v) {
      if (v.extra.isEmpty) return;
      try {
        final decoded = jsonDecode(v.extra);
        if (decoded is Map) {
          current = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        Log.warn('unparseable extra on view ${view.id}, not writing: $e');
        current = {};
      }
    },
    (error) => Log.warn('failed to load view ${view.id} for color: $error'),
  );

  if (colorId == null || colorId.isEmpty) {
    current.remove(kPageColorExtKey);
  } else {
    current[kPageColorExtKey] = colorId;
  }

  await ViewBackendService.updateView(
    viewId: view.id,
    extra: jsonEncode(current),
  );
}

/// The sentinel colour used for the "Default" (inherit) swatch: transparent, so
/// [FlowyColorPicker]'s "selected == option.color" check-marks it when the page
/// carries no colour of its own.
const Color _kDefaultSwatch = Colors.transparent;

/// The Page tab's colour control — a swatch button that opens a picker of
/// theme-aware tint presets, a Default (clear) option, and a custom-colour
/// field. Page-level, so it reads the view from [ViewBloc] like the page
/// direction / theme toggles and is always enabled.
class PageColorControl extends StatefulWidget {
  const PageColorControl({super.key});

  @override
  State<PageColorControl> createState() => _PageColorControlState();
}

class _PageColorControlState extends State<PageColorControl> {
  final PopoverController _controller = PopoverController();
  final TextEditingController _hexController = TextEditingController();
  final TextEditingController _opacityController = TextEditingController();
  bool _isHovering = false;

  @override
  void dispose() {
    _hexController.dispose();
    _opacityController.dispose();
    super.dispose();
  }

  void _store(BuildContext context, String? colorId) {
    final view = context.read<ViewBloc>().state.view;
    setPageColor(view, colorId).then((_) {
      if (context.mounted) {
        // The write lands in the backend; the ViewBloc must re-read it or the
        // sheet keeps its old colour until the page is reopened.
        context.read<ViewBloc>().add(const ViewEvent.initial());
      }
    });
    _controller.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final view = context.watch<ViewBloc>().state.view;
    final previewColor = resolvePageSheetColor(view.pageColorId, context);

    Widget child = Container(
      height: kRibbonButtonSize,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6.0),
      decoration: BoxDecoration(
        color: _isHovering ? theme.fillColorScheme.contentHover : null,
        borderRadius: BorderRadius.circular(theme.borderRadius.m),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The current colour as a small swatch; a bordered ring when the page
          // inherits (no colour set).
          Container(
            width: 16.0,
            height: 16.0,
            decoration: BoxDecoration(
              color: previewColor,
              shape: BoxShape.circle,
              border: Border.all(color: theme.borderColorScheme.tertiary),
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 16.0,
            color: theme.iconColorScheme.primary,
          ),
        ],
      ),
    );

    child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: child,
    );

    return FlowyTooltip(
      message: 'Page colour',
      preferBelow: true,
      child: AppFlowyPopover(
        controller: _controller,
        direction: PopoverDirection.bottomWithLeftAligned,
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 420),
        offset: const Offset(0, 4),
        // Opening steals focus from the editor; hold the notifier so the user's
        // place in the document is not lost while they pick a colour (the same
        // politeness the ribbon dropdowns apply — harmless here since a page
        // colour does not read the selection).
        onOpen: () => keepEditorFocusNotifier.increase(),
        onClose: () => keepEditorFocusNotifier.decrease(),
        popupBuilder: (_) => _PageColorMenu(
          selected: previewColor ?? _kDefaultSwatch,
          hexController: _hexController,
          opacityController: _opacityController,
          onPick: (id) => _store(context, id),
        ),
        child: child,
      ),
    );
  }
}

/// One selectable option in the colour grid.
@immutable
class _ColorChoice {
  const _ColorChoice({required this.color, required this.label, required this.id});

  final Color color;
  final String label;

  /// The value to store: a tint id, or '' for the Default (clear) swatch.
  final String id;
}

class _PageColorMenu extends StatelessWidget {
  const _PageColorMenu({
    required this.selected,
    required this.hexController,
    required this.opacityController,
    required this.onPick,
  });

  final Color selected;
  final TextEditingController hexController;
  final TextEditingController opacityController;

  /// Called with the id to store (a tint id, a custom hex, or null to clear).
  final void Function(String? id) onPick;

  @override
  Widget build(BuildContext context) {
    final choices = <_ColorChoice>[
      const _ColorChoice(color: _kDefaultSwatch, label: 'Default', id: ''),
      for (final tint in FlowyTint.values)
        _ColorChoice(
          color: tint.color(context),
          label: tint.tintName(AppFlowyEditorL10n.current),
          id: tint.id,
        ),
    ];

    // Material so the custom-colour ExpansionTile below has an ink surface.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 232,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  for (final choice in choices)
                    _Swatch(
                      choice: choice,
                      isSelected: selected == choice.color,
                      onTap: () => onPick(choice.id.isEmpty ? null : choice.id),
                    ),
                ],
              ),
            ),
            CustomColorItem(
              colorController: hexController,
              opacityController: opacityController,
              onSubmittedColorHex: (hex) => onPick(hex),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single round colour swatch. The Default swatch (transparent) reads as an
/// outlined empty circle; a selected swatch gets a ring and a check.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.isSelected,
    required this.onTap,
  });

  final _ColorChoice choice;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isDefault = choice.id.isEmpty;

    return FlowyTooltip(
      message: choice.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26.0,
            height: 26.0,
            decoration: BoxDecoration(
              color: choice.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? theme.borderColorScheme.themeThick
                    : theme.borderColorScheme.tertiary,
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 14.0,
                    color: theme.iconColorScheme.primary,
                  )
                : (isDefault
                    ? Icon(
                        Icons.not_interested,
                        size: 14.0,
                        color: theme.iconColorScheme.tertiary,
                      )
                    : null),
          ),
        ),
      ),
    );
  }
}
