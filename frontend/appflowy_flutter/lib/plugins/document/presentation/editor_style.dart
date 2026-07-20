import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/font_colors.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_menu.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/util/color_contrast.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/appearance_defaults.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universal_platform/universal_platform.dart';

import 'editor_plugins/desktop_toolbar/link/link_hover_menu.dart';
import 'editor_plugins/toolbar_item/more_option_toolbar_item.dart';

class EditorStyleCustomizer {
  EditorStyleCustomizer({
    required this.context,
    required this.padding,
    this.width,
    this.editorState,
    this.pageTextDirection,
  });

  final BuildContext context;
  final EdgeInsets padding;
  final double? width;
  final EditorState? editorState;

  /// [fork:rtl] This page's own direction ('ltr' / 'rtl' / 'auto'), when it has
  /// one. Null means the page has never been set and should follow the app-wide
  /// default, which is the pre-Phase-2 behaviour every existing page keeps.
  /// See `page_text_direction.dart`.
  final String? pageTextDirection;

  static const double maxDocumentWidth = 480 * 4;
  static const double minDocumentWidth = 480;

  /// Bare margin between the editor pane edge and the document, before any
  /// allowance for the block option gutter.
  static const double baseDocumentMargin = 40.0;

  /// [fork:rtl] Gap between the block option buttons and the block's text,
  /// consumed by `editor_configuration.dart`'s `actionTrailingBuilder`.
  ///
  /// Lives here rather than at the use site because [blockOptionGutterWidth]
  /// has to stay in step with it — that coupling is the whole reason the page
  /// margins drifted (see below).
  static const double blockActionTrailingGap = 30.0;

  /// Total horizontal space the block option menu takes out of every block.
  ///
  /// ⚠️ This is **in-flow space, not an overlay.** The option menu is a real
  /// `Row` child on the *leading* side of each block
  /// (`block_component_action_wrapper.dart`), held open permanently by
  /// `Visibility(maintainSize: true)`, so it pushes the text inward on that
  /// side only. The trailing side must reserve the same amount by hand or the
  /// page ends up visibly lopsided.
  ///
  /// = [optionMenuWidth] (the buttons: 18 + 2 + 18 + 5 ≈ 43, rounded to 44)
  /// + [blockActionTrailingGap].
  ///
  /// History worth keeping: upstream returns `SizedBox.shrink()` for this
  /// trailing gap, so upstream's gutter really is ~44 — which is why
  /// [optionMenuWidth] alone was the correct compensation there. Our commit
  /// `ffc069150` widened the gap to 30px on live-testing feedback and grew the
  /// gutter to ~73 without updating any of the three places that compensate
  /// for it, leaving every page 29px lopsided. Derive, don't re-hardcode.
  static double get blockOptionGutterWidth =>
      UniversalPlatform.isMobile ? 0 : optionMenuWidth + blockActionTrailingGap;

  /// Where body text actually starts, measured from the editor pane edge.
  ///
  /// Both edges land here once [documentPaddingFor] has balanced the gutter, so
  /// anything that needs to line up with the text — the title, the page icon,
  /// the header toolbar — should measure against this rather than re-deriving
  /// it from a padding side.
  static double get documentTextInset =>
      baseDocumentMargin + blockOptionGutterWidth;

  /// Extra inset that lines a *non-block* widget up with the body text.
  ///
  /// Blocks get the gutter for free (it is a child of their own `Row`); the
  /// header widgets are returned outside that wrapper — see
  /// `custom_page_block_component.dart:89`, which returns the header raw — so
  /// they have to add it by hand.
  ///
  /// Takes the padding rather than a direction because the header widgets sit
  /// under the *app layout's* `Directionality`, which is not necessarily the
  /// page's direction. The padding already encodes the page's direction (the
  /// smaller side is the one the gutter is on), so reading it back keeps the
  /// header in step with the body even when page and layout disagree.
  static EdgeInsets textAlignmentInsetFor(EdgeInsets documentPadding) =>
      documentPadding.left <= documentPadding.right
          ? EdgeInsets.only(left: blockOptionGutterWidth)
          : EdgeInsets.only(right: blockOptionGutterWidth);

  /// [fork:rtl] Which way the page's *header* widgets — the title and the
  /// icon/cover row — should read.
  ///
  /// Padding alone was not enough: the header sits under the **app layout's**
  /// `Directionality`, so setting a page to LTR while the app is laid out RTL
  /// left the title right-aligned and hard against the wrong margin. The body
  /// text moved and the title did not (reported 2026-07-20).
  ///
  /// [defaultTextDirection] is `EditorStyle.defaultTextDirection`, which already
  /// resolves page-setting-then-global (see `desktop()` below) — so this deals
  /// only in what that produced, and never re-reads the page itself.
  ///
  /// `auto` is resolved from the title's own text, matching how each block
  /// decides for itself. Note the text is the *committed* view name, so an
  /// `auto` title settles its direction when the name commits rather than on
  /// every keystroke; explicit ltr/rtl are immediate.
  ///
  /// Inherited quirk worth knowing: `determineTextDirection` counts ASCII
  /// digits as LTR evidence, so a title like "2026 סיכום" resolves LTR. That is
  /// the editor's behaviour for every block too, so the title stays consistent
  /// with the body; it is asserted in `page_margin_and_direction_test.dart`.
  static ui.TextDirection headerTextDirection({
    required String? defaultTextDirection,
    required String text,
    required ui.TextDirection layoutDirection,
  }) {
    switch (defaultTextDirection) {
      case blockComponentTextDirectionLTR:
        return ui.TextDirection.ltr;
      case blockComponentTextDirectionRTL:
        return ui.TextDirection.rtl;
      case blockComponentTextDirectionAuto:
        // No strongly-directional character (empty, digits, punctuation) means
        // there is nothing to go on — defer to the frame rather than guessing.
        return determineTextDirection(text) ?? layoutDirection;
      default:
        return layoutDirection;
    }
  }

  static EdgeInsets get documentPadding =>
      documentPaddingFor(ui.TextDirection.ltr);

  /// [fork:rtl] Direction-aware document padding, balanced against the block
  /// option gutter so both page margins render equal.
  ///
  /// The gutter ([blockOptionGutterWidth]) eats in-flow space on the *leading*
  /// side of every block, so that side needs only [baseDocumentMargin] of
  /// padding to reach its target margin, while the trailing side has to pay the
  /// gutter's width itself. Both text edges then land at
  /// `baseDocumentMargin + blockOptionGutterWidth` from the editor pane.
  ///
  /// Measured on the real macOS target (1332px pane, before this fix):
  /// LTR text edges sat at 113 / 84, RTL at 40 / 157 — lopsided by 29px, which
  /// is exactly `blockOptionGutterWidth - optionMenuWidth`. Verify changes here
  /// by measuring rendered text edges, never by eye: the earlier attempt at
  /// this blamed the `Center()` in `custom_page_block_component.dart:119`, but
  /// that centring is symmetric by construction (the padding sits *inside* the
  /// `maxWidth` constraint, so `Center` sees a fixed-width box) and cannot
  /// shift the column at all.
  ///
  /// Note the leading margin is unchanged by this: only the trailing side
  /// widens, to match. Nothing moves inward.
  static EdgeInsets documentPaddingFor(ui.TextDirection direction) {
    if (UniversalPlatform.isMobile) {
      return EdgeInsets.zero;
    }
    final gutterSide = baseDocumentMargin + blockOptionGutterWidth;
    return direction == ui.TextDirection.rtl
        ? EdgeInsets.only(left: gutterSide, right: baseDocumentMargin)
        : EdgeInsets.only(left: baseDocumentMargin, right: gutterSide);
  }

  static double get nodeHorizontalPadding =>
      UniversalPlatform.isMobile ? 24 : 0;

  // [fork:rtl] Upstream's `documentPaddingWithOptionMenu` was removed here. It
  // read `documentPadding + EdgeInsets.only(left: optionMenuWidth)`, which
  // produced equal padding on both sides back when the gutter was exactly
  // `optionMenuWidth` — i.e. it expressed the same idea as [documentTextInset],
  // but hardcoded against a gutter width that no longer holds. It had no
  // callers left, so a stale duplicate of that arithmetic was a trap rather
  // than a convenience. Use [documentTextInset] if a symmetric inset is needed.

  static double get optionMenuWidth => UniversalPlatform.isMobile ? 0 : 44;

  static Color? toolbarHoverColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.secondary
        : AFThemeExtension.of(context).toolbarHoverColor;
  }

  EditorStyle style() {
    if (UniversalPlatform.isDesktopOrWeb) {
      return desktop();
    } else if (UniversalPlatform.isMobile) {
      return mobile();
    }
    throw UnimplementedError();
  }

  EditorStyle desktop() {
    final theme = Theme.of(context);
    final afThemeExtension = AFThemeExtension.of(context);
    final appearanceFont = context.read<AppearanceSettingsCubit>().state.font;
    final appearance = context.read<DocumentAppearanceCubit>().state;
    final fontSize = appearance.fontSize;
    String fontFamily = appearance.fontFamily;
    if (fontFamily.isEmpty && appearanceFont.isNotEmpty) {
      fontFamily = appearanceFont;
    }

    final cursorColor = (editorState?.editable ?? true)
        ? (appearance.cursorColor ??
            DefaultAppearanceSettings.getDefaultCursorColor(context))
        : Colors.transparent;

    return EditorStyle.desktop(
      padding: padding,
      maxWidth: width,
      cursorColor: cursorColor,
      selectionColor: appearance.selectionColor ??
          DefaultAppearanceSettings.getDefaultSelectionColor(context),
      // [fork:rtl] The page's own direction wins; the global preference is the
      // fallback for pages that have never been set.
      defaultTextDirection:
          pageTextDirection ?? appearance.defaultTextDirection,
      textStyleConfiguration: TextStyleConfiguration(
        lineHeight: 1.4,
        // on Windows, if applyHeightToFirstAscent is true, the first line will be too high.
        // it will cause the first line not aligned with the prefix icon.
        applyHeightToFirstAscent: UniversalPlatform.isWindows ? false : true,
        applyHeightToLastDescent: true,
        text: baseTextStyle(fontFamily).copyWith(
          fontSize: fontSize,
          color: afThemeExtension.onBackground,
        ),
        bold: baseTextStyle(fontFamily, fontWeight: FontWeight.bold).copyWith(
          fontWeight: FontWeight.w600,
        ),
        italic: baseTextStyle(fontFamily).copyWith(fontStyle: FontStyle.italic),
        underline: baseTextStyle(fontFamily).copyWith(
          decoration: TextDecoration.underline,
        ),
        strikethrough: baseTextStyle(fontFamily).copyWith(
          decoration: TextDecoration.lineThrough,
        ),
        href: baseTextStyle(fontFamily).copyWith(
          // [fork:page-surface] Keep links legible on this page's background —
          // the default cyan is only ~2.2:1 on a white sheet (color_contrast.dart).
          color: ensureContrast(
            theme.colorScheme.primary,
            theme.colorScheme.surface,
          ),
          decoration: TextDecoration.underline,
        ),
        code: GoogleFonts.robotoMono(
          textStyle: baseTextStyle(fontFamily).copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.normal,
            color: Colors.red,
            backgroundColor:
                theme.colorScheme.inverseSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      textSpanDecorator: customizeAttributeDecorator,
      textScaleFactor:
          context.watch<AppearanceSettingsCubit>().state.textScaleFactor,
      textSpanOverlayBuilder: _buildTextSpanOverlay,
    );
  }

  EditorStyle mobile() {
    final afThemeExtension = AFThemeExtension.of(context);
    final pageStyle = context.read<DocumentPageStyleBloc>().state;
    final theme = Theme.of(context);
    final fontSize = pageStyle.fontLayout.fontSize;
    final lineHeight = pageStyle.lineHeightLayout.lineHeight;
    final fontFamily = pageStyle.fontFamily ??
        context.read<AppearanceSettingsCubit>().state.font;
    // [fork:rtl] Same precedence as desktop(): page setting, then global.
    final defaultTextDirection = pageTextDirection ??
        context.read<DocumentAppearanceCubit>().state.defaultTextDirection;
    final textScaleFactor =
        context.read<AppearanceSettingsCubit>().state.textScaleFactor;
    final baseTextStyle = this.baseTextStyle(fontFamily);

    return EditorStyle.mobile(
      padding: padding,
      defaultTextDirection: defaultTextDirection,
      textStyleConfiguration: TextStyleConfiguration(
        lineHeight: lineHeight,
        text: baseTextStyle.copyWith(
          fontSize: fontSize,
          color: afThemeExtension.onBackground,
        ),
        bold: baseTextStyle.copyWith(fontWeight: FontWeight.w600),
        italic: baseTextStyle.copyWith(fontStyle: FontStyle.italic),
        underline: baseTextStyle.copyWith(decoration: TextDecoration.underline),
        strikethrough: baseTextStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        ),
        href: baseTextStyle.copyWith(
          // [fork:page-surface] See desktop() — keep links legible on the page.
          color: ensureContrast(
            theme.colorScheme.primary,
            theme.colorScheme.surface,
          ),
          decoration: TextDecoration.underline,
        ),
        code: GoogleFonts.robotoMono(
          textStyle: baseTextStyle.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.normal,
            color: Colors.red,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      textSpanDecorator: customizeAttributeDecorator,
      magnifierSize: const Size(144, 96),
      textScaleFactor: textScaleFactor,
      mobileDragHandleLeftExtend: 12.0,
      mobileDragHandleWidthExtend: 24.0,
      textSpanOverlayBuilder: _buildTextSpanOverlay,
    );
  }

  TextStyle headingStyleBuilder(int level) {
    final String? fontFamily;
    final List<double> fontSizes;
    final double fontSize;
    if (UniversalPlatform.isMobile) {
      final state = context.read<DocumentPageStyleBloc>().state;
      fontFamily = state.fontFamily;
      fontSize = state.fontLayout.fontSize;
      fontSizes = state.fontLayout.headingFontSizes;
    } else {
      fontFamily = context
          .read<DocumentAppearanceCubit>()
          .state
          .fontFamily
          .orDefault(context.read<AppearanceSettingsCubit>().state.font);
      fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
      fontSizes = [
        fontSize + 16,
        fontSize + 12,
        fontSize + 8,
        fontSize + 4,
        fontSize + 2,
        fontSize,
      ];
    }
    return baseTextStyle(fontFamily, fontWeight: FontWeight.w600).copyWith(
      fontSize: fontSizes.elementAtOrNull(level - 1) ?? fontSize,
    );
  }

  CodeBlockStyle codeBlockStyleBuilder() {
    final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
    final fontFamily =
        context.read<DocumentAppearanceCubit>().state.codeFontFamily;

    return CodeBlockStyle(
      textStyle: baseTextStyle(fontFamily).copyWith(
        fontSize: fontSize,
        height: 1.5,
        color: AFThemeExtension.of(context).onBackground,
      ),
      backgroundColor: AFThemeExtension.of(context).calloutBGColor,
      foregroundColor: AFThemeExtension.of(context).textColor.withAlpha(155),
    );
  }

  TextStyle calloutBlockStyleBuilder() {
    if (UniversalPlatform.isMobile) {
      final afThemeExtension = AFThemeExtension.of(context);
      final pageStyle = context.read<DocumentPageStyleBloc>().state;
      final fontSize = pageStyle.fontLayout.fontSize;
      final fontFamily = pageStyle.fontFamily ?? defaultFontFamily;
      final baseTextStyle = this.baseTextStyle(fontFamily);
      return baseTextStyle.copyWith(
        fontSize: fontSize,
        color: afThemeExtension.onBackground,
      );
    } else {
      final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
      return baseTextStyle(null).copyWith(
        fontSize: fontSize,
        height: 1.5,
      );
    }
  }

  TextStyle outlineBlockPlaceholderStyleBuilder() {
    final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
    return TextStyle(
      fontFamily: defaultFontFamily,
      fontSize: fontSize,
      height: 1.5,
      color: AFThemeExtension.of(context).onBackground.withValues(alpha: 0.6),
    );
  }

  TextStyle subPageBlockTextStyleBuilder() {
    if (UniversalPlatform.isMobile) {
      final pageStyle = context.read<DocumentPageStyleBloc>().state;
      final fontSize = pageStyle.fontLayout.fontSize;
      final fontFamily = pageStyle.fontFamily ?? defaultFontFamily;
      final baseTextStyle = this.baseTextStyle(fontFamily);
      return baseTextStyle.copyWith(
        fontSize: fontSize,
      );
    } else {
      final fontSize = context.read<DocumentAppearanceCubit>().state.fontSize;
      return baseTextStyle(null).copyWith(
        fontSize: fontSize,
        height: 1.5,
      );
    }
  }

  SelectionMenuStyle selectionMenuStyleBuilder() {
    final theme = Theme.of(context);
    final afThemeExtension = AFThemeExtension.of(context);
    return SelectionMenuStyle(
      selectionMenuBackgroundColor: theme.cardColor,
      selectionMenuItemTextColor: afThemeExtension.onBackground,
      selectionMenuItemIconColor: afThemeExtension.onBackground,
      selectionMenuItemSelectedIconColor: theme.colorScheme.onSurface,
      selectionMenuItemSelectedTextColor: theme.colorScheme.onSurface,
      selectionMenuItemSelectedColor: afThemeExtension.greyHover,
      selectionMenuUnselectedLabelColor: afThemeExtension.onBackground,
      selectionMenuDividerColor: afThemeExtension.greyHover,
      selectionMenuLinkBorderColor: afThemeExtension.greyHover,
      selectionMenuInvalidLinkColor: afThemeExtension.onBackground,
      selectionMenuButtonColor: afThemeExtension.greyHover,
      selectionMenuButtonTextColor: afThemeExtension.onBackground,
      selectionMenuButtonIconColor: afThemeExtension.onBackground,
      selectionMenuButtonBorderColor: afThemeExtension.greyHover,
      selectionMenuTabIndicatorColor: afThemeExtension.greyHover,
    );
  }

  InlineActionsMenuStyle inlineActionsMenuStyleBuilder() {
    final theme = Theme.of(context);
    final afThemeExtension = AFThemeExtension.of(context);
    return InlineActionsMenuStyle(
      backgroundColor: theme.cardColor,
      groupTextColor: afThemeExtension.onBackground.withValues(alpha: .8),
      menuItemTextColor: afThemeExtension.onBackground,
      menuItemSelectedColor: theme.colorScheme.secondary,
      menuItemSelectedTextColor: theme.colorScheme.onSurface,
    );
  }

  TextStyle baseTextStyle(String? fontFamily, {FontWeight? fontWeight}) {
    if (fontFamily == null) {
      return TextStyle(fontWeight: fontWeight);
    } else if (fontFamily == defaultFontFamily) {
      return TextStyle(fontFamily: fontFamily, fontWeight: fontWeight);
    }

    try {
      return getGoogleFontSafely(fontFamily, fontWeight: fontWeight);
    } on Exception {
      if ([defaultFontFamily, builtInCodeFontFamily].contains(fontFamily)) {
        return TextStyle(fontFamily: fontFamily, fontWeight: fontWeight);
      }

      return TextStyle(fontWeight: fontWeight);
    }
  }

  InlineSpan customizeAttributeDecorator(
    BuildContext context,
    Node node,
    int index,
    TextInsert text,
    TextSpan before,
    TextSpan after,
  ) {
    final attributes = text.attributes;
    if (attributes == null) {
      return before;
    }

    final suggestion = attributes[AiWriterBlockKeys.suggestion] as String?;
    final newStyle = suggestion == null
        ? after.style
        : _styleSuggestion(after.style, suggestion);

    if (attributes.backgroundColor != null) {
      final color = EditorFontColors.fromBuiltInColors(
        context,
        attributes.backgroundColor!,
      );
      if (color != null) {
        return TextSpan(
          text: before.text,
          style: newStyle?.merge(
            TextStyle(backgroundColor: color),
          ),
        );
      }
    }

    // try to refresh font here.
    if (attributes.fontFamily != null) {
      try {
        if (before.text?.contains('_regular') == true) {
          getGoogleFontSafely(attributes.fontFamily!.parseFontFamilyName());
        } else {
          return TextSpan(
            text: before.text,
            style: newStyle?.merge(
              getGoogleFontSafely(attributes.fontFamily!),
            ),
          );
        }
      } catch (_) {
        // ignore
      }
    }

    // Inline Mentions (Page Reference, Date, Reminder, etc.)
    final mention =
        attributes[MentionBlockKeys.mention] as Map<String, dynamic>?;
    if (mention != null) {
      final type = mention[MentionBlockKeys.type];
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: newStyle,
        child: MentionBlock(
          key: ValueKey(
            switch (type) {
              MentionType.page => mention[MentionBlockKeys.pageId],
              MentionType.date => mention[MentionBlockKeys.date],
              _ => MentionBlockKeys.mention,
            },
          ),
          node: node,
          index: index,
          mention: mention,
          textStyle: newStyle,
        ),
      );
    }

    // customize the inline math equation block
    final formula = attributes[InlineMathEquationKeys.formula];
    if (formula is String) {
      return WidgetSpan(
        style: after.style,
        alignment: PlaceholderAlignment.middle,
        child: InlineMathEquation(
          node: node,
          index: index,
          formula: formula,
          textStyle: after.style ?? style().textStyleConfiguration.text,
        ),
      );
    }

    // customize the link on mobile
    final href = attributes[AppFlowyRichTextKeys.href] as String?;
    if (UniversalPlatform.isMobile && href != null) {
      return TextSpan(style: before.style, text: text.text);
    }

    if (suggestion != null) {
      return TextSpan(
        text: before.text,
        style: newStyle,
      );
    }

    if (href != null) {
      return TextSpan(
        style: before.style,
        text: text.text,
        mouseCursor: SystemMouseCursors.click,
      );
    } else {
      return before;
    }
  }

  Widget buildToolbarItemTooltip(
    BuildContext context,
    String id,
    String message,
    Widget child,
  ) {
    final tooltipMessage = _buildTooltipMessage(id, message);
    child = FlowyTooltip(
      richMessage: tooltipMessage,
      preferBelow: false,
      verticalOffset: 24,
      child: child,
    );

    // the align/font toolbar item doesn't need the hover effect
    final toolbarItemsWithoutHover = {
      kFontToolbarItemId,
      kAlignToolbarItemId,
    };

    if (!toolbarItemsWithoutHover.contains(id)) {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: FlowyHover(
          style: HoverStyle(
            hoverColor: Colors.grey.withValues(alpha: 0.3),
          ),
          child: child,
        ),
      );
    }

    return child;
  }

  TextSpan _buildTooltipMessage(String id, String message) {
    final markdownItemTooltips = {
      'underline': (LocaleKeys.toolbar_underline.tr(), 'U'),
      'bold': (LocaleKeys.toolbar_bold.tr(), 'B'),
      'italic': (LocaleKeys.toolbar_italic.tr(), 'I'),
      'strikethrough': (LocaleKeys.toolbar_strike.tr(), 'Shift+S'),
      'code': (LocaleKeys.toolbar_inlineCode.tr(), 'E'),
      'editor.inline_math_equation': (
        LocaleKeys.document_plugins_createInlineMathEquation.tr(),
        'Shift+E'
      ),
    };

    final markdownItemIds = markdownItemTooltips.keys.toSet();
    // the items without shortcuts
    if (!markdownItemIds.contains(id)) {
      return TextSpan(
        text: message,
        style: context.tooltipTextStyle(),
      );
    }

    final tooltip = markdownItemTooltips[id];
    if (tooltip == null) {
      return TextSpan(
        text: message,
        style: context.tooltipTextStyle(),
      );
    }

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: '${tooltip.$1}\n',
          style: context.tooltipTextStyle(),
        ),
        TextSpan(
          text: (Platform.isMacOS ? '⌘+' : 'Ctrl+') + tooltip.$2,
          style: context.tooltipTextStyle()?.copyWith(
                color: Theme.of(context).hintColor,
              ),
        ),
      ],
    );

    return textSpan;
  }

  TextStyle? _styleSuggestion(TextStyle? style, String suggestion) {
    if (style == null) {
      return null;
    }
    final isLight = Theme.of(context).isLightMode;
    final textColor = isLight ? Color(0xFF007296) : Color(0xFF49CFF4);
    final underlineColor = isLight ? Color(0x33005A7A) : Color(0x3349CFF4);
    return switch (suggestion) {
      AiWriterBlockKeys.suggestionOriginal => style.copyWith(
          color: Theme.of(context).disabledColor,
          decoration: TextDecoration.lineThrough,
        ),
      AiWriterBlockKeys.suggestionReplacement => style.copyWith(
          color: textColor,
          decoration: TextDecoration.underline,
          decorationColor: underlineColor,
          decorationThickness: 1.0,
        ),
      _ => style,
    };
  }

  List<Widget> _buildTextSpanOverlay(
    BuildContext context,
    Node node,
    SelectableMixin delegate,
  ) {
    final delta = node.delta;
    if (delta == null) return [];
    final widgets = <Widget>[];
    final textInserts = delta.whereType<TextInsert>();
    int index = 0;
    final editorState = context.read<EditorState>();
    for (final textInsert in textInserts) {
      if (textInsert.attributes?.href != null) {
        final nodeSelection = Selection(
          start: Position(path: node.path, offset: index),
          end: Position(
            path: node.path,
            offset: index + textInsert.length,
          ),
        );
        final rectList = delegate.getRectsInSelection(nodeSelection);
        if (rectList.isNotEmpty) {
          for (final rect in rectList) {
            widgets.add(
              Positioned(
                left: rect.left,
                top: rect.top,
                child: SizedBox(
                  width: rect.width,
                  height: rect.height,
                  child: LinkHoverTrigger(
                    editorState: editorState,
                    selection: nodeSelection,
                    attribute: textInsert.attributes!,
                    node: node,
                    size: rect.size,
                  ),
                ),
              ),
            );
          }
        }
      }
      index += textInsert.length;
    }
    return widgets;
  }
}
