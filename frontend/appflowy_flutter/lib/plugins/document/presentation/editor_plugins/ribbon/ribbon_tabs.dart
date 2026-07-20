// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// The ribbon's contents: four tabs (Content, Page, Elements, Tools), grouped
// into captioned clusters.
//
// Two rules govern this file:
//
//  1. Actions are invoked through the *existing* command or editor API, never
//     re-implemented. Where a capability is a registered CommandShortcutEvent,
//     `execute()` runs it and `key` resolves the live (rebindable) shortcut for
//     the tooltip — so a rebind in Settings → Shortcuts is reflected instead of
//     a hardcoded string.
//  2. Capabilities AppFlowy does not have yet are present as `comingSoon`
//     buttons rather than omitted, so the ribbon shows its full intended shape
//     from day one. Each later phase lights some of these up.
//
// The state of every item here was audited against the app and the editor fork
// on 2026-07-19; see the inventory table in specs/ribbon-menu.md.

import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
// [fork:rtl] Phase 2 — per-page direction.
import 'package:appflowy/plugins/document/application/page_text_direction.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/align_toolbar_item/custom_text_align_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_copy_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_cut_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_paste_command.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'ribbon_action.dart';

/// Alignment values accepted by [blockComponentAlign] (fork:
/// `base_component_keys.dart` documents these as left / right / center).
const String _alignLeft = 'left';
const String _alignCenter = 'center';
const String _alignRight = 'right';

/// True only when there is genuinely nowhere to apply an action — i.e. no
/// cursor in the editor at all. A *collapsed* cursor is fine: inline marks set
/// a pending style (`EditorState.toggledStyle`) and block actions apply to the
/// current block.
bool _hasTarget(EditorState editorState) => editorState.selection != null;

/// True only when a range of text is actually selected. Used by actions that
/// genuinely cannot work from a bare cursor, such as copy and cut.
bool _hasRange(EditorState editorState) {
  final selection = editorState.selection;
  return selection != null && !selection.isCollapsed;
}

/// Whether [attribute] is currently in force — either applied across the
/// selection, or pending for the next typed character.
bool _isMarkActive(EditorState editorState, String attribute) {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }
  if (editorState.toggledStyle.containsKey(attribute)) {
    return editorState.toggledStyle[attribute] == true;
  }
  if (selection.isCollapsed) {
    return false;
  }
  final nodes = editorState.getNodesInSelection(selection);
  return nodes.allSatisfyInSelection(
    selection,
    (delta) =>
        delta.isNotEmpty &&
        delta.everyAttributes((attr) => attr[attribute] == true),
  );
}

/// Builds an action for a simple inline mark (bold, italic, …).
///
/// `toggleAttribute` already handles the collapsed-cursor case by setting a
/// pending style, so these work with just a caret — no extra handling needed.
RibbonAction _markAction({
  required String id,
  required String label,
  required String attribute,
  required FlowySvgData icon,
  required String shortcutCommandId,
}) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    shortcutCommandId: shortcutCommandId,
    isEnabled: _hasTarget,
    isHighlighted: (editorState) => _isMarkActive(editorState, attribute),
    onPressed: (_, editorState) => editorState.toggleAttribute(attribute),
  );
}

/// Builds an action that runs an existing [CommandShortcutEvent].
///
/// The command's own `key` is reused as the shortcut id, so the tooltip shows
/// whatever that command is currently bound to.
RibbonAction _commandAction({
  required String id,
  required String label,
  required CommandShortcutEvent command,
  required FlowySvgData icon,
  bool Function(EditorState)? isEnabled,
}) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    shortcutCommandId: command.key,
    isEnabled: isEnabled ?? _hasTarget,
    onPressed: (_, editorState) => command.execute(editorState),
  );
}

/// Sets a block-level attribute on every block touched by the selection.
Future<void> _setBlockAttribute(
  EditorState editorState,
  String key,
  String value,
) async {
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }
  await editorState.updateNode(
    selection,
    (node) => node.copyWith(
      attributes: {...node.attributes, key: value},
    ),
  );
}

bool _blockAttributeIs(EditorState editorState, String key, String value) {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }
  final nodes = editorState.getNodesInSelection(selection);
  return nodes.isNotEmpty && nodes.every((n) => n.attributes[key] == value);
}

RibbonAction _blockAttributeAction({
  required String id,
  required String label,
  required String attributeKey,
  required String value,
  required FlowySvgData icon,
  String? shortcutCommandId,
}) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    shortcutCommandId: shortcutCommandId,
    isEnabled: _hasTarget,
    isHighlighted: (editorState) =>
        _blockAttributeIs(editorState, attributeKey, value),
    onPressed: (_, editorState) =>
        _setBlockAttribute(editorState, attributeKey, value),
  );
}

/// [fork:rtl] A whole-page direction toggle (Phase 2).
///
/// Unlike the Text tab's direction buttons — which set a `blockComponentTextDirection`
/// attribute on the selected block — these persist to the *view*, in
/// `View.extra`, so the choice belongs to the page and survives reopening.
///
/// Both its state and its effect live outside the editor, so it reads the view
/// from [ViewBloc] rather than from [EditorState]: hence
/// [RibbonAction.isHighlightedInContext] and the unused `editorState` below.
/// It is also deliberately always enabled — a page has a direction whether or
/// not the cursor is currently in it.
RibbonAction _pageDirectionAction({
  required String id,
  required String label,
  required PageTextDirection direction,
  required FlowySvgData icon,
}) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    isEnabled: (_) => true,
    // watch, not read: this is evaluated during the button's build, and the
    // toggled-on state has to follow the view changing underneath it.
    isHighlightedInContext: (context, _) =>
        context.watch<ViewBloc>().state.view.pageTextDirection == direction,
    onPressed: (context, _) {
      final view = context.read<ViewBloc>().state.view;
      // Pressing the active direction again clears it, returning the page to
      // the app-wide default — the same "click to toggle off" the block-level
      // direction buttons have.
      final next = view.pageTextDirection == direction
          ? PageTextDirection.inherit
          : direction;
      unawaited(
        setPageTextDirection(view, next).then((_) {
          if (context.mounted) {
            // The write lands in the backend; the ViewBloc has to be told to
            // re-read it, or the editor keeps rendering the old direction until
            // the page is reopened.
            context.read<ViewBloc>().add(const ViewEvent.initial());
          }
        }),
      );
    },
  );
}

/// An action that runs an existing command but reports its on/off state from a
/// block attribute — the alignment buttons, which are registered commands *and*
/// need to render as toggled when their alignment is in force.
RibbonAction _commandActionWithBlockState({
  required String id,
  required String label,
  required CommandShortcutEvent command,
  required String attributeKey,
  required String value,
  required FlowySvgData icon,
}) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    shortcutCommandId: command.key,
    isEnabled: _hasTarget,
    isHighlighted: (editorState) =>
        _blockAttributeIs(editorState, attributeKey, value),
    onPressed: (_, editorState) => command.execute(editorState),
  );
}

/// Converts the selected blocks to [type], or back to a paragraph if they are
/// already that type — the usual list-button toggle behaviour.
///
/// Uses the editor's own `formatNode`, which handles the insert/delete pairing
/// and selection restoration correctly. Hand-rolling that transaction is a
/// known way to corrupt the document.
Future<void> _toggleBlockType(EditorState editorState, String type) async {
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }
  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) {
    return;
  }
  final allAreType = nodes.every((n) => n.type == type);
  final target = allAreType ? ParagraphBlockKeys.type : type;

  await editorState.formatNode(
    selection,
    (node) => node.copyWith(type: target),
  );
}

bool _isBlockType(EditorState editorState, String type) {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }
  final nodes = editorState.getNodesInSelection(selection);
  return nodes.isNotEmpty && nodes.every((n) => n.type == type);
}

RibbonAction _blockTypeAction({
  required String id,
  required String label,
  required String type,
  required FlowySvgData icon,
}) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    isEnabled: _hasTarget,
    isHighlighted: (editorState) => _isBlockType(editorState, type),
    onPressed: (_, editorState) => _toggleBlockType(editorState, type),
  );
}

/// A placeholder for a capability AppFlowy does not have yet.
RibbonAction _comingSoon(String id, String label, [FlowySvgData? icon]) {
  return RibbonAction(
    id: id,
    label: label,
    icon: icon,
    comingSoon: true,
  );
}

/// The four tabs.
///
/// Built as a function rather than a const list because the actions close over
/// editor APIs and localisation, and because later phases will make some of
/// these depend on the current view.
List<RibbonTab> buildRibbonTabs() {
  return [
    _contentTab(),
    _pageTab(),
    _elementsTab(),
    _toolsTab(),
  ];
}

RibbonTab _contentTab() {
  return RibbonTab(
    id: 'content',
    label: 'Content',
    groups: [
      RibbonGroup(
        id: 'clipboard',
        caption: 'Clipboard',
        actions: [
          _commandAction(
            id: 'cut',
            label: 'Cut',
            command: customCutCommand,
            icon: FlowySvgs.m_table_quick_action_cut_s,
            isEnabled: _hasRange,
          ),
          _commandAction(
            id: 'copy',
            label: 'Copy',
            command: customCopyCommand,
            icon: FlowySvgs.m_table_quick_action_copy_s,
            isEnabled: _hasRange,
          ),
          _commandAction(
            id: 'paste',
            label: 'Paste',
            command: customPasteCommand,
            icon: FlowySvgs.m_table_quick_action_paste_s,
          ),
        ],
      ),
      RibbonGroup(
        id: 'font',
        caption: 'Font',
        actions: [
          _markAction(
            id: 'bold',
            label: 'Bold',
            attribute: AppFlowyRichTextKeys.bold,
            icon: FlowySvgs.toolbar_bold_m,
            shortcutCommandId: 'toggle bold',
          ),
          _markAction(
            id: 'italic',
            label: 'Italic',
            attribute: AppFlowyRichTextKeys.italic,
            icon: FlowySvgs.toolbar_inline_italic_m,
            shortcutCommandId: 'toggle italic',
          ),
          _markAction(
            id: 'underline',
            label: 'Underline',
            attribute: AppFlowyRichTextKeys.underline,
            icon: FlowySvgs.toolbar_underline_m,
            shortcutCommandId: 'toggle underline',
          ),
          _markAction(
            id: 'strikethrough',
            label: 'Strikethrough',
            attribute: AppFlowyRichTextKeys.strikethrough,
            icon: FlowySvgs.type_strikethrough_m,
            shortcutCommandId: 'toggle strikethrough',
          ),
          _markAction(
            id: 'code',
            label: 'Inline code',
            attribute: AppFlowyRichTextKeys.code,
            icon: FlowySvgs.toolbar_inline_code_m,
            shortcutCommandId: 'toggle code',
          ),
          // Font family / colour / highlight are popover pickers rather than
          // plain buttons. They exist today in the floating toolbar; rebuilding
          // their popovers against the ribbon button is Phase 5 work, so they
          // are honest placeholders here rather than half-wired controls.
          _comingSoon('font_family', 'Font'),
          _comingSoon('font_color', 'Font colour'),
          _comingSoon('highlight_color', 'Highlight colour'),
          // Attribute exists in the fork but nothing writes it (audit 2026-07-19).
          _comingSoon('font_size', 'Font size'),
        ],
      ),
      RibbonGroup(
        id: 'paragraph',
        caption: 'Paragraph',
        actions: [
          _blockTypeAction(
            id: 'bulleted_list',
            label: 'Bulleted list',
            type: BulletedListBlockKeys.type,
            icon: FlowySvgs.type_bulleted_list_m,
          ),
          _blockTypeAction(
            id: 'numbered_list',
            label: 'Numbered list',
            type: NumberedListBlockKeys.type,
            icon: FlowySvgs.type_numbered_list_m,
          ),
          // Multilevel list is indent/outdent applied to an existing list,
          // which the two buttons below already provide.
          _commandAction(
            id: 'indent',
            label: 'Increase indent',
            command: indentCommand,
            icon: FlowySvgs.m_aa_indent_m,
          ),
          _commandAction(
            id: 'outdent',
            label: 'Decrease indent',
            command: outdentCommand,
            icon: FlowySvgs.m_aa_outdent_m,
          ),
          _commandActionWithBlockState(
            id: 'align_left',
            label: 'Align left',
            command: customTextLeftAlignCommand,
            attributeKey: blockComponentAlign,
            value: _alignLeft,
            icon: FlowySvgs.toolbar_text_align_left_m,
          ),
          _commandActionWithBlockState(
            id: 'align_center',
            label: 'Align centre',
            command: customTextCenterAlignCommand,
            attributeKey: blockComponentAlign,
            value: _alignCenter,
            icon: FlowySvgs.toolbar_text_align_center_m,
          ),
          _commandActionWithBlockState(
            id: 'align_right',
            label: 'Align right',
            command: customTextRightAlignCommand,
            attributeKey: blockComponentAlign,
            value: _alignRight,
            icon: FlowySvgs.toolbar_text_align_right_m,
          ),
          // Only three align values exist in the editor today.
          _comingSoon('justify', 'Justify'),
          _comingSoon('line_spacing', 'Line spacing'),
          _comingSoon('paragraph_spacing', 'Paragraph spacing'),
        ],
      ),
      RibbonGroup(
        id: 'direction',
        caption: 'Direction',
        actions: [
          _blockAttributeAction(
            id: 'text_ltr',
            label: 'Left to right',
            attributeKey: blockComponentTextDirection,
            value: blockComponentTextDirectionLTR,
            icon: FlowySvgs.textdirection_ltr_m,
          ),
          _blockAttributeAction(
            id: 'text_rtl',
            label: 'Right to left',
            attributeKey: blockComponentTextDirection,
            value: blockComponentTextDirectionRTL,
            icon: FlowySvgs.textdirection_rtl_m,
          ),
          _blockAttributeAction(
            id: 'text_auto',
            label: 'Automatic direction',
            attributeKey: blockComponentTextDirection,
            value: blockComponentTextDirectionAuto,
            icon: FlowySvgs.textdirection_auto_m,
          ),
        ],
      ),
      RibbonGroup(
        id: 'editing',
        caption: 'Editing',
        actions: [
          // Link is a popover (URL entry), same reasoning as the colour pickers.
          _comingSoon('link', 'Link'),
          _comingSoon('sentence_case', 'Sentence case'),
          _comingSoon('clear_formatting', 'Clear formatting'),
          // Both need a new delta attribute in the editor fork — Phase 4.
          _comingSoon('superscript', 'Superscript'),
          _comingSoon('subscript', 'Subscript'),
          _comingSoon('footnote', 'Footnote'),
          // Needs absolute positioning the flow layout does not support.
          _comingSoon('text_box', 'Text box'),
        ],
      ),
    ],
  );
}

RibbonTab _pageTab() {
  return RibbonTab(
    id: 'page',
    label: 'Page',
    groups: [
      RibbonGroup(
        id: 'page_structure',
        caption: 'Structure',
        actions: [
          _comingSoon('table_of_contents', 'Table of contents'),
        ],
      ),
      RibbonGroup(
        id: 'page_direction',
        caption: 'Page direction',
        actions: [
          _pageDirectionAction(
            id: 'page_ltr',
            label: 'Page left to right',
            direction: PageTextDirection.ltr,
            icon: FlowySvgs.textdirection_ltr_m,
          ),
          _pageDirectionAction(
            id: 'page_rtl',
            label: 'Page right to left',
            direction: PageTextDirection.rtl,
            icon: FlowySvgs.textdirection_rtl_m,
          ),
          _pageDirectionAction(
            id: 'page_auto',
            label: 'Automatic page direction',
            direction: PageTextDirection.auto,
            icon: FlowySvgs.textdirection_auto_m,
          ),
        ],
      ),
      RibbonGroup(
        id: 'page_layout',
        caption: 'Layout',
        actions: [
          _comingSoon('page_colour', 'Page colour'),
          _comingSoon('margins', 'Margins'),
          _comingSoon('ruler', 'Show ruler'),
        ],
      ),
    ],
  );
}

RibbonTab _elementsTab() {
  return RibbonTab(
    id: 'elements',
    label: 'Elements',
    groups: [
      RibbonGroup(
        id: 'insert',
        caption: 'Insert',
        actions: [
          // These exist via the slash menu; giving them ribbon buttons means
          // driving the same insert paths, which is Phase 5 work rather than
          // frame work.
          _comingSoon('table', 'Table'),
          _comingSoon('image', 'Image'),
          _comingSoon('equation', 'Equation'),
        ],
      ),
      RibbonGroup(
        id: 'media',
        caption: 'Media',
        actions: [
          // Renders legacy blocks but has no insertion path or player.
          _comingSoon('video', 'Video'),
          _comingSoon('audio', 'Audio'),
        ],
      ),
      RibbonGroup(
        id: 'graphics',
        caption: 'Graphics',
        actions: [
          // Each needs a new block type and rendering surface — own specs.
          _comingSoon('drawing', 'Drawing'),
          _comingSoon('diagram', 'Diagram'),
          _comingSoon('chart', 'Chart'),
        ],
      ),
    ],
  );
}

RibbonTab _toolsTab() {
  return RibbonTab(
    id: 'tools',
    label: 'Tools',
    groups: [
      RibbonGroup(
        id: 'share',
        caption: 'Share',
        actions: [
          _comingSoon('publish', 'Publish page'),
        ],
      ),
      RibbonGroup(
        id: 'appearance',
        caption: 'Appearance',
        actions: [
          RibbonAction(
            id: 'theme_toggle',
            label: 'Light / dark mode',
            icon: FlowySvgs.settings_selected_theme_m,
            // Always available — unlike the formatting buttons this needs no
            // cursor, so it must not inherit the default "needs a selection".
            isEnabled: (_) => true,
            onPressed: (context, _) =>
                context.read<AppearanceSettingsCubit>().toggleThemeMode(),
          ),
        ],
      ),
      RibbonGroup(
        id: 'ai',
        caption: 'AI',
        actions: [
          // Both are large, external-service features with their own specs.
          _comingSoon('translate', 'Translate'),
          _comingSoon('transcribe', 'Transcribe'),
          _comingSoon('record', 'Record'),
        ],
      ),
    ],
  );
}
