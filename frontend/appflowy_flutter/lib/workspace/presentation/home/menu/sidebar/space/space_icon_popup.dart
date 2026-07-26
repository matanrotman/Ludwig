import 'dart:convert';
import 'dart:math';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/util/color_contrast.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart' hide Icon;

final builtInSpaceColors = [
  '0xFFA34AFD',
  '0xFFFB006D',
  '0xFF00C8FF',
  '0xFFFFBA00',
  '0xFFF254BC',
  '0xFF2AC985',
  '0xFFAAD93D',
  '0xFF535CE4',
  '0xFF808080',
  '0xFFD2515F',
  '0xFF409BF8',
  '0xFFFF8933',
];

String generateRandomSpaceColor() {
  final random = Random();
  return builtInSpaceColors[random.nextInt(builtInSpaceColors.length)];
}

final builtInSpaceIcons =
    List.generate(15, (index) => 'space_icon_${index + 1}');

class SpaceIconPopup extends StatefulWidget {
  const SpaceIconPopup({
    super.key,
    this.icon,
    this.iconColor,
    this.cornerRadius = 16,
    this.space,
    required this.onIconChanged,
    this.dimension = 32,
    this.svgSize,
    this.showBackground = true,
  });

  final String? icon;
  final String? iconColor;
  final ViewPB? space;
  final void Function(String? icon, String? color) onIconChanged;
  final double cornerRadius;

  /// [fork:folder] How the trigger preview is drawn. These exist because the
  /// sidebar's space header opens this picker by clicking the icon *in place*,
  /// so the trigger IS the sidebar's icon and has to look like it — small, and
  /// without the filled badge (the header row already carries the space colour
  /// as a tint; repeating it as a vivid badge said the same thing twice).
  ///
  /// The defaults reproduce the previous behaviour exactly, so every other
  /// caller — the create-space and manage-space dialogs — is unchanged.
  final double dimension;

  /// Glyph size. Null keeps the original sizing, which deliberately *overflows*
  /// the legacy `space_icon_*` tiles so they bleed to the edges of the badge.
  /// That only reads correctly at the full 32pt tile with a background behind
  /// it; at sidebar size it just crops the glyph, which is why the header
  /// passes an explicit size.
  final double? svgSize;

  final bool showBackground;

  @override
  State<SpaceIconPopup> createState() => _SpaceIconPopupState();
}

class _SpaceIconPopupState extends State<SpaceIconPopup> {
  late ValueNotifier<String?> selectedIcon = ValueNotifier<String?>(
    widget.icon,
  );
  late ValueNotifier<String> selectedColor = ValueNotifier<String>(
    widget.iconColor ?? builtInSpaceColors.first,
  );

  @override
  void dispose() {
    selectedColor.dispose();
    selectedIcon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      offset: const Offset(0, 4),
      constraints: BoxConstraints.loose(const Size(360, 432)),
      margin: const EdgeInsets.all(0),
      direction: PopoverDirection.bottomWithCenterAligned,
      child: _buildPreview(),
      popupBuilder: (context) {
        return FlowyIconEmojiPicker(
          tabs: const [PickerTabType.icon],
          onSelectedEmoji: (r) {
            if (r.type == FlowyIconType.icon) {
              try {
                final iconsData = IconsData.fromJson(jsonDecode(r.emoji));
                final color = iconsData.color;
                selectedIcon.value =
                    '${iconsData.groupName}/${iconsData.iconName}';
                if (color != null) {
                  selectedColor.value = color;
                }
                widget.onIconChanged(selectedIcon.value, selectedColor.value);
              } on FormatException catch (e) {
                selectedIcon.value = '';
                widget.onIconChanged(selectedIcon.value, selectedColor.value);
                Log.warn('SpaceIconPopup onSelectedEmoji error:$e');
              }
            }
            PopoverContainer.of(context).close();
          },
        );
      },
    );
  }

  /// The picker's trigger: what the space's icon looks like right now, including
  /// a live preview of whatever is being hovered in the open picker.
  ///
  /// [fork:folder] All three branches honour [SpaceIconPopup.dimension],
  /// [SpaceIconPopup.svgSize] and [SpaceIconPopup.showBackground], because the
  /// sidebar header uses this widget as its icon *in place*. Before, the branches
  /// hardcoded a 32pt tile with the badge always on — and drew the legacy
  /// `space_icon_*` glyphs at 42pt inside it, relying on the clip to make them
  /// bleed. At the header's 22pt that produced a cropped fragment of a glyph on a
  /// badge that was supposed to be gone.
  Widget _buildIconTile(BuildContext context, String? value, String color) {
    // Nothing picked yet: SpaceIcon already handles the name-initial fallback
    // and the no-badge contrast tinting, so defer to it rather than repeat it.
    if (value == null) {
      if (widget.space == null) {
        return DefaultSpaceIcon(
          cornerRadius: widget.cornerRadius,
          dimension: widget.dimension,
          iconDimension: widget.svgSize ?? widget.dimension,
        );
      }
      return SpaceIcon(
        dimension: widget.dimension,
        space: widget.space!,
        svgSize: widget.svgSize ?? 24,
        cornerRadius: widget.cornerRadius,
        showBackground: widget.showBackground,
      );
    }

    // A space can carry an empty or malformed colour (spaces created before the
    // picker existed do), so never parse it eagerly — the previous code only got
    // away with `int.parse` because it sat behind the icon-content check.
    final tint = _parseColor(color);

    // With a badge behind it the glyph is knocked out in the surface colour.
    // Without one it has to carry the space's colour itself, nudged until it
    // reads against the sidebar — the same rule SpaceIcon applies. With no
    // usable colour at all, fall back to plain foreground rather than vanish.
    final surface = Theme.of(context).colorScheme.surface;
    final Color glyphColor;
    if (widget.showBackground) {
      glyphColor = surface;
    } else if (tint != null) {
      glyphColor = ensureContrast(tint, surface, minRatio: 3.0);
    } else {
      glyphColor = Theme.of(context).colorScheme.onSurface;
    }

    final Widget glyph;
    if (value.contains('space_icon')) {
      glyph = FlowySvg(
        FlowySvgData('assets/flowy_icons/16x/$value.svg'),
        // The legacy tiles are drawn to bleed past the badge; that only works
        // at full size with a background, so an explicit svgSize wins.
        size: Size.square(widget.svgSize ?? 42),
        color: glyphColor,
      );
    } else {
      final content = kIconGroups?.findSvgContent(value);
      if (content == null) {
        return const SizedBox.shrink();
      }
      glyph = FlowySvg.string(
        content,
        size: Size.square(widget.svgSize ?? 24),
        color: glyphColor,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.cornerRadius),
      child: Container(
        width: widget.dimension,
        height: widget.dimension,
        color: widget.showBackground ? tint : null,
        child: Align(child: glyph),
      ),
    );
  }

  /// Null rather than throwing, for the empty/legacy/malformed cases.
  Color? _parseColor(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return Color(int.parse(value));
    } catch (e) {
      Log.error('Failed to parse space icon color: $e, value: $value');
      return null;
    }
  }

  Widget _buildPreview() {
    bool onHover = false;
    return StatefulBuilder(
      builder: (context, setState) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (event) => setState(() => onHover = true),
          onExit: (event) => setState(() => onHover = false),
          child: ValueListenableBuilder(
            valueListenable: selectedColor,
            builder: (_, color, __) {
              return ValueListenableBuilder(
                valueListenable: selectedIcon,
                builder: (_, value, __) {
                  final child = _buildIconTile(context, value, color);

                  if (onHover) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Opacity(opacity: 0.2, child: child),
                        ),
                        const Center(
                          child: FlowySvg(
                            FlowySvgs.view_item_rename_s,
                            size: Size.square(20),
                          ),
                        ),
                      ],
                    );
                  }
                  return child;
                },
              );
            },
          ),
        );
      },
    );
  }
}

class SpaceIconPicker extends StatefulWidget {
  const SpaceIconPicker({
    super.key,
    required this.onIconChanged,
    this.skipFirstNotification = false,
    this.icon,
    this.iconColor,
  });

  final bool skipFirstNotification;
  final void Function(String icon, String color) onIconChanged;
  final String? icon;
  final String? iconColor;

  @override
  State<SpaceIconPicker> createState() => _SpaceIconPickerState();
}

class _SpaceIconPickerState extends State<SpaceIconPicker> {
  late ValueNotifier<String> selectedColor =
      ValueNotifier<String>(widget.iconColor ?? builtInSpaceColors.first);
  late ValueNotifier<String> selectedIcon =
      ValueNotifier<String>(widget.icon ?? builtInSpaceIcons.first);

  @override
  void initState() {
    super.initState();

    if (!widget.skipFirstNotification) {
      widget.onIconChanged(selectedIcon.value, selectedColor.value);
    }

    selectedColor.addListener(_onColorChanged);
    selectedIcon.addListener(_onIconChanged);
  }

  void _onColorChanged() {
    widget.onIconChanged(selectedIcon.value, selectedColor.value);
  }

  void _onIconChanged() {
    widget.onIconChanged(selectedIcon.value, selectedColor.value);
  }

  @override
  void dispose() {
    selectedColor.removeListener(_onColorChanged);
    selectedColor.dispose();

    selectedIcon.removeListener(_onIconChanged);
    selectedIcon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FlowyText.regular(
          LocaleKeys.space_spaceIconBackground.tr(),
          color: Theme.of(context).hintColor,
        ),
        const VSpace(10.0),
        _Colors(
          selectedColor: selectedColor.value,
          onColorSelected: (color) => selectedColor.value = color,
        ),
        const VSpace(12.0),
        FlowyText.regular(
          LocaleKeys.space_spaceIcon.tr(),
          color: Theme.of(context).hintColor,
        ),
        const VSpace(10.0),
        ValueListenableBuilder(
          valueListenable: selectedColor,
          builder: (_, value, ___) => _Icons(
            selectedColor: value,
            selectedIcon: selectedIcon.value,
            onIconSelected: (icon) => selectedIcon.value = icon,
          ),
        ),
      ],
    );
  }
}

class _Colors extends StatefulWidget {
  const _Colors({
    required this.selectedColor,
    required this.onColorSelected,
  });

  final String selectedColor;
  final void Function(String color) onColorSelected;

  @override
  State<_Colors> createState() => _ColorsState();
}

class _ColorsState extends State<_Colors> {
  late String selectedColor = widget.selectedColor;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 6,
      mainAxisSpacing: 4.0,
      children: builtInSpaceColors.map((color) {
        return GestureDetector(
          onTap: () {
            setState(() => selectedColor = color);

            widget.onColorSelected(color);
          },
          child: Container(
            margin: const EdgeInsets.all(2.0),
            padding: const EdgeInsets.all(2.0),
            decoration: selectedColor == color
                ? ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(
                        width: 1.50,
                        strokeAlign: BorderSide.strokeAlignOutside,
                        color: Color(0xFF00BCF0),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  )
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(int.parse(color)),
                borderRadius: BorderRadius.circular(20.0),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Icons extends StatefulWidget {
  const _Icons({
    required this.selectedColor,
    required this.selectedIcon,
    required this.onIconSelected,
  });

  final String selectedColor;
  final String selectedIcon;
  final void Function(String color) onIconSelected;

  @override
  State<_Icons> createState() => _IconsState();
}

class _IconsState extends State<_Icons> {
  late String selectedIcon = widget.selectedIcon;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 5,
      mainAxisSpacing: 8.0,
      crossAxisSpacing: 12.0,
      children: builtInSpaceIcons.map((icon) {
        return GestureDetector(
          onTap: () {
            setState(() => selectedIcon = icon);

            widget.onIconSelected(icon);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: FlowySvg(
              FlowySvgData('assets/flowy_icons/16x/$icon.svg'),
              color: Color(int.parse(widget.selectedColor)),
              blendMode: BlendMode.srcOut,
            ),
          ),
        );
      }).toList(),
    );
  }
}
