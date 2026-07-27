import 'dart:io';
import 'dart:math';
// [fork:rtl] Prefixed to match editor_style.dart, whose direction helpers this
// file calls.
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/migration/editor_migration.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide UploadImageMenu;
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/rounded_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

import 'cover_title.dart';

const double kCoverHeight = 280.0;
const double kIconHeight = 60.0;
const double kToolbarHeight = 40.0; // with padding to the top

/// [fork:no-titles] The vertical space a titleless page reserves where its title
/// would have been — see `specs/no-titles.md`.
///
/// Derived from [kCoverTitleFontSize] rather than picked, so it follows if the
/// title's size ever changes. The 1.4 is the title field's own line box: a 40pt
/// font in a borderless `TextField`, which is what used to sit here.
///
/// **This is the one number to change if the top of a titleless page reads too
/// tight or too airy.**
const double kTitlelessHeaderGap = kCoverTitleFontSize * 1.4;

/// [fork:no-titles] Space above the "Add Cover / Add icon" row on a titleless
/// page with no cover, so it is not pinned to the top edge of the sheet.
///
/// Its companion: [kTitlelessHeaderGap] holds the header off the *text*, this
/// holds it off the *top*. Both exist because the title used to do the job.
const double kTitlelessHeaderTopGap = 24.0;

// Remove this widget if the desktop support immersive cover.
class DocumentHeaderBlockKeys {
  const DocumentHeaderBlockKeys._();

  static const String coverType = 'cover_selection_type';
  static const String coverDetails = 'cover_selection';
  static const String icon = 'selected_icon';
}

// for the version under 0.5.5, including 0.5.5
enum CoverType {
  none,
  color,
  file,
  asset;

  static CoverType fromString(String? value) {
    if (value == null) {
      return CoverType.none;
    }
    return CoverType.values.firstWhere(
      (e) => e.toString() == value,
      orElse: () => CoverType.none,
    );
  }
}

// This key is used to intercept the selection event in the document cover widget.
const _interceptorKey = 'document_cover_widget_interceptor';

class DocumentCoverWidget extends StatefulWidget {
  const DocumentCoverWidget({
    super.key,
    required this.node,
    required this.editorState,
    required this.onIconChanged,
    required this.view,
    required this.tabs,
  });

  final Node node;
  final EditorState editorState;
  final ValueChanged<EmojiIconData> onIconChanged;
  final ViewPB view;
  final List<PickerTabType> tabs;

  @override
  State<DocumentCoverWidget> createState() => _DocumentCoverWidgetState();
}

class _DocumentCoverWidgetState extends State<DocumentCoverWidget> {
  CoverType get coverType => CoverType.fromString(
        widget.node.attributes[DocumentHeaderBlockKeys.coverType],
      );

  String? get coverDetails =>
      widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];

  String? get icon => widget.node.attributes[DocumentHeaderBlockKeys.icon];

  bool get hasIcon => viewIcon.emoji.isNotEmpty;

  bool get hasCover =>
      coverType != CoverType.none ||
      (cover != null && cover?.type != PageStyleCoverImageType.none);

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  EmojiIconData viewIcon = EmojiIconData.none();

  PageStyleCover? cover;
  late ViewPB view;
  late final ViewListener viewListener;
  int retryCount = 0;

  final isCoverTitleHovered = ValueNotifier<bool>(false);

  late final gestureInterceptor = SelectionGestureInterceptor(
    key: _interceptorKey,
    canTap: (details) => !_isTapInBounds(details.globalPosition),
    canPanStart: (details) => !_isDragInBounds(details.globalPosition),
  );

  @override
  void initState() {
    super.initState();
    final icon = widget.view.icon;
    viewIcon = EmojiIconData.fromViewIconPB(icon);
    cover = widget.view.cover;
    view = widget.view;
    widget.node.addListener(_reload);
    widget.editorState.service.selectionService
        .registerGestureInterceptor(gestureInterceptor);

    viewListener = ViewListener(viewId: widget.view.id)
      ..start(
        // [fork:title-fix] The parameter was named `view`, shadowing the state
        // field of the same name, so `view = view` was a self-assignment and
        // the field kept its initial (often empty-named) snapshot forever.
        onViewUpdated: (updatedView) {
          setState(() {
            viewIcon = EmojiIconData.fromViewIconPB(updatedView.icon);
            cover = updatedView.cover;
            view = updatedView;
          });
        },
      );
  }

  @override
  void dispose() {
    viewListener.stop();
    widget.node.removeListener(_reload);
    isCoverTitleHovered.dispose();
    widget.editorState.service.selectionService
        .unregisterGestureInterceptor(_interceptorKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.editorState.editable,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final offset = _calculateIconLeft(context, constraints);
          return Padding(
            // [fork:no-titles] A titleless page needs air ABOVE the header too,
            // not only below it. On an ordinary page the title's own line box
            // gives the "Add Cover / Add icon" row somewhere to sit; strip the
            // title and the row ends up pinned to the top of the sheet (user,
            // session 15: "Add cover and icon now don't have breathing space").
            //
            // Only when there is no cover: a cover already fills the top of the
            // page, and padding above it would leave a strip of desk showing
            // through where the image should run to the edge.
            padding: EdgeInsets.only(
              top: hasCover ? 0 : kTitlelessHeaderTopGap,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: _calculateOverallHeight(),
                      // [fork:rtl] The "Add icon"/"Add cover" toolbar must follow
                      // the PAGE's direction like the title, icon and the cover's
                      // own buttons do — otherwise on an RTL page it stays pinned
                      // to the left and reads as sitting under the icon rather
                      // than across from it (user report 2026-07-25). One wrapper
                      // flips both the button order and, via
                      // AlignmentDirectional.bottomStart inside, which edge the
                      // row hugs.
                      child: Directionality(
                        textDirection: _headerDirection(context),
                        child: DocumentHeaderToolbar(
                          onIconOrCoverChanged: _saveIconOrCover,
                          node: widget.node,
                          editorState: widget.editorState,
                          hasCover: hasCover,
                          hasIcon: hasIcon,
                          offset: offset,
                          isCoverTitleHovered: isCoverTitleHovered,
                          documentId: view.id,
                          tabs: widget.tabs,
                        ),
                      ),
                    ),
                    if (hasCover)
                      DocumentCover(
                        view: view,
                        editorState: widget.editorState,
                        node: widget.node,
                        coverType: coverType,
                        coverDetails: coverDetails,
                        onChangeCover: (type, details) =>
                            _saveIconOrCover(cover: (type, details)),
                      ),
                    _buildAlignedCoverIcon(context),
                  ],
                ),
                // [fork:no-titles] **PHASE 5 — there is no title box any more.**
                // A page is named by its first line, everywhere, with no second
                // kind of page left in the wild: the one-off migration moved
                // every existing name into its document as line one.
                //
                // Omitted entirely rather than sized to zero. An invisible
                // `CoverTitle` still holds a focus node and still seeds itself
                // from the view's name, and this header is rebuilt whenever a
                // paste grows the document (it is item 0 of a virtualized list).
                // That combination is precisely what produced session 11's title
                // bug, and there is no reason to keep a dormant copy of it.
                //
                // The space it occupied IS kept. Without it the "Add Cover / Add
                // icon" row sits directly on the first line of text (user,
                // session 15: "too close to first line of text") — on the old
                // page it was the title that held those apart.
                const SizedBox(height: kTitlelessHeaderGap),
              ],
            ),
          );
        },
      ),
    );
  }

  /// [fork:rtl] The direction the header should read in — the page's, not the
  /// app layout's. See `EditorStyleCustomizer.headerTextDirection`.
  ui.TextDirection _headerDirection(BuildContext context) =>
      EditorStyleCustomizer.headerTextDirection(
        defaultTextDirection:
            widget.editorState.editorStyle.defaultTextDirection,
        text: view.name,
        layoutDirection: Directionality.of(context),
      );

  // [fork:no-titles] Phase 5 removed `_buildAlignedTitle` — the title field it
  // drew no longer exists on any page. `cover_title.dart` itself is left on disk
  // unused, the same retired-but-kept treatment the sidebar's replaced widgets
  // got, so a future upstream merge has something to land against.

  Widget _buildAlignedCoverIcon(BuildContext context) {
    if (!hasIcon) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: hasCover ? kToolbarHeight - kIconHeight / 2 : kToolbarHeight,
      left: 0,
      right: 0,
      // [fork:rtl] The icon belongs to the title, so it follows the same
      // direction — otherwise an RTL page's icon sits at the far end of the row
      // from the title beneath it.
      child: Directionality(
        textDirection: _headerDirection(context),
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  widget.editorState.editorStyle.maxWidth ?? double.infinity,
            ),
            // [fork:rtl] Same alignment fix as the title above.
            padding: widget.editorState.editorStyle.padding +
                EditorStyleCustomizer.textAlignmentInsetFor(
                  widget.editorState.editorStyle.padding,
                ),
            child: Row(
              children: [
                DocumentIcon(
                  editorState: widget.editorState,
                  node: widget.node,
                  icon: viewIcon,
                  documentId: view.id,
                  onChangeIcon: (icon) => _saveIconOrCover(icon: icon),
                ),
                Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _reload() => setState(() {});

  double _calculateIconLeft(BuildContext context, BoxConstraints constraints) {
    final editorState = context.read<EditorState>();
    final appearanceCubit = context.read<DocumentAppearanceCubit>();

    final renderBox = editorState.renderBox;

    if (renderBox == null || !renderBox.hasSize) {}

    var renderBoxWidth = 0.0;
    if (renderBox != null && renderBox.hasSize) {
      renderBoxWidth = renderBox.size.width;
    } else if (retryCount <= 3) {
      retryCount++;
      // this is a workaround for the issue that the renderBox is not initialized
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _reload();
      });
      return 0;
    }

    // if the renderBox width equals to 0, it means the editor is not initialized
    final editorWidth = renderBoxWidth != 0
        ? min(renderBoxWidth, appearanceCubit.state.width)
        : appearanceCubit.state.width;

    // [fork:rtl] Centring gap, then however far in the body text starts. This
    // read `documentPadding.right` before, which was only ever a stand-in for
    // the same quantity and drifted 29px out of date once the gutter grew.
    final leftOffset = (constraints.maxWidth - editorWidth) / 2.0 +
        EditorStyleCustomizer.documentTextInset;

    // ensure the offset is not negative
    return max(0, leftOffset);
  }

  double _calculateOverallHeight() {
    final height = switch ((hasIcon, hasCover)) {
      (true, true) => kCoverHeight + kToolbarHeight,
      (true, false) => 50 + kIconHeight + kToolbarHeight,
      (false, true) => kCoverHeight + kToolbarHeight,
      (false, false) => kToolbarHeight,
    };

    return height;
  }

  void _saveIconOrCover({
    (CoverType, String?)? cover,
    EmojiIconData? icon,
  }) async {
    if (!widget.editorState.editable) {
      return;
    }

    final transaction = widget.editorState.transaction;
    final coverType = widget.node.attributes[DocumentHeaderBlockKeys.coverType];
    final coverDetails =
        widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];
    final Map<String, dynamic> attributes = {
      DocumentHeaderBlockKeys.coverType: coverType,
      DocumentHeaderBlockKeys.coverDetails: coverDetails,
      DocumentHeaderBlockKeys.icon:
          widget.node.attributes[DocumentHeaderBlockKeys.icon],
      CustomImageBlockKeys.imageType: '1',
    };
    if (cover != null) {
      attributes[DocumentHeaderBlockKeys.coverType] = cover.$1.toString();
      attributes[DocumentHeaderBlockKeys.coverDetails] = cover.$2;
    }
    if (icon != null) {
      attributes[DocumentHeaderBlockKeys.icon] = icon.emoji;
      widget.onIconChanged(icon);
    }

    // compatible with version <= 0.5.5.
    transaction.updateNode(widget.node, attributes);
    await widget.editorState.apply(transaction);

    // compatible with version > 0.5.5.
    //
    // [fork:rtl] ⚠️ `view`, NOT `widget.view`. This is the bug that made
    // deleting a cover revert an RTL page to LTR (user report 2026-07-25).
    // `migrateCoverIfNeeded` merges the new cover into `view.extra` and writes
    // the result back — so it must merge into the CURRENT extra. `widget.view`
    // is the snapshot captured when the page was opened, so any per-page
    // setting written since (direction, theme, colour, margins — all of which
    // live in `extra`) was absent from it and got erased on the write.
    //
    // The state field `view` is kept fresh by the ViewListener in initState
    // for exactly this reason. Same root cause as the 2026-07-19 title bug:
    // a stale ViewPB captured at open time. Anything in this file that writes
    // `extra` must use `view`.
    EditorMigration.migrateCoverIfNeeded(
      view,
      attributes,
      overwrite: true,
    );
  }

  bool _isTapInBounds(Offset offset) {
    if (_renderBox == null) {
      return false;
    }

    final localPosition = _renderBox!.globalToLocal(offset);
    return _renderBox!.paintBounds.contains(localPosition);
  }

  bool _isDragInBounds(Offset offset) {
    if (_renderBox == null) {
      return false;
    }

    final localPosition = _renderBox!.globalToLocal(offset);
    return _renderBox!.paintBounds.contains(localPosition);
  }
}

@visibleForTesting
class DocumentHeaderToolbar extends StatefulWidget {
  const DocumentHeaderToolbar({
    super.key,
    required this.node,
    required this.editorState,
    required this.hasCover,
    required this.hasIcon,
    required this.onIconOrCoverChanged,
    required this.offset,
    this.documentId,
    required this.isCoverTitleHovered,
    required this.tabs,
  });

  final Node node;
  final EditorState editorState;
  final bool hasCover;
  final bool hasIcon;
  final void Function({(CoverType, String?)? cover, EmojiIconData? icon})
      onIconOrCoverChanged;
  final double offset;
  final String? documentId;
  final ValueNotifier<bool> isCoverTitleHovered;
  final List<PickerTabType> tabs;

  @override
  State<DocumentHeaderToolbar> createState() => _DocumentHeaderToolbarState();
}

class _DocumentHeaderToolbarState extends State<DocumentHeaderToolbar> {
  final _popoverController = PopoverController();

  bool isHidden = UniversalPlatform.isDesktopOrWeb;
  bool isPopoverOpen = false;

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      // [fork:rtl] Directional so the row hugs the reading direction's starting
      // edge. Identical to the old `Alignment.bottomLeft` on an LTR page.
      alignment: AlignmentDirectional.bottomStart,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: widget.offset),
      child: SizedBox(
        height: 28,
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.isCoverTitleHovered,
          builder: (context, isHovered, child) {
            return Visibility(
              visible: !isHidden || isPopoverOpen || isHovered,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buildRowChildren(),
              ),
            );
          },
        ),
      ),
    );

    if (UniversalPlatform.isDesktopOrWeb) {
      child = MouseRegion(
        opaque: false,
        onEnter: (event) => setHidden(false),
        onExit: isPopoverOpen ? null : (_) => setHidden(true),
        child: child,
      );
    }

    return child;
  }

  List<Widget> buildRowChildren() {
    if (widget.hasCover && widget.hasIcon) {
      return [];
    }

    final List<Widget> children = [];

    if (!widget.hasCover) {
      children.add(
        FlowyButton(
          leftIconSize: const Size.square(18),
          onTap: () => widget.onIconOrCoverChanged(
            cover: UniversalPlatform.isDesktopOrWeb
                ? (CoverType.asset, '1')
                : (CoverType.color, '0xffe8e0ff'),
          ),
          useIntrinsicWidth: true,
          leftIcon: const FlowySvg(FlowySvgs.add_cover_s),
          text: FlowyText.small(
            LocaleKeys.document_plugins_cover_addCover.tr(),
            color: Theme.of(context).hintColor,
          ),
        ),
      );
    }

    if (widget.hasIcon) {
      children.add(
        FlowyButton(
          onTap: () => widget.onIconOrCoverChanged(icon: EmojiIconData.none()),
          useIntrinsicWidth: true,
          leftIcon: const FlowySvg(FlowySvgs.add_icon_s),
          iconPadding: 4.0,
          text: FlowyText.small(
            LocaleKeys.document_plugins_cover_removeIcon.tr(),
            color: Theme.of(context).hintColor,
          ),
        ),
      );
    } else {
      Widget child = FlowyButton(
        useIntrinsicWidth: true,
        leftIcon: const FlowySvg(FlowySvgs.add_icon_s),
        iconPadding: 4.0,
        text: FlowyText.small(
          LocaleKeys.document_plugins_cover_addIcon.tr(),
          color: Theme.of(context).hintColor,
        ),
        onTap: UniversalPlatform.isDesktop
            ? null
            : () async {
                final result = await context.push<EmojiIconData>(
                  MobileEmojiPickerScreen.routeName,
                );
                if (result != null) {
                  widget.onIconOrCoverChanged(icon: result);
                }
              },
      );

      if (UniversalPlatform.isDesktop) {
        child = AppFlowyPopover(
          onClose: () => setState(() => isPopoverOpen = false),
          controller: _popoverController,
          offset: const Offset(0, 8),
          direction: PopoverDirection.bottomWithCenterAligned,
          constraints: BoxConstraints.loose(const Size(360, 380)),
          margin: EdgeInsets.zero,
          child: child,
          popupBuilder: (BuildContext popoverContext) {
            isPopoverOpen = true;
            return FlowyIconEmojiPicker(
              tabs: widget.tabs,
              documentId: widget.documentId,
              onSelectedEmoji: (r) {
                widget.onIconOrCoverChanged(icon: r.data);
                if (!r.keepOpen) _popoverController.close();
              },
            );
          },
        );
      }

      children.add(child);
    }

    return children;
  }

  void setHidden(bool value) {
    if (isHidden == value) return;
    setState(() {
      isHidden = value;
    });
  }
}

@visibleForTesting
class DocumentCover extends StatefulWidget {
  const DocumentCover({
    super.key,
    required this.view,
    required this.node,
    required this.editorState,
    required this.coverType,
    this.coverDetails,
    required this.onChangeCover,
  });

  final ViewPB view;
  final Node node;
  final EditorState editorState;
  final CoverType coverType;
  final String? coverDetails;
  final void Function(CoverType type, String? details) onChangeCover;

  @override
  State<DocumentCover> createState() => DocumentCoverState();
}

class DocumentCoverState extends State<DocumentCover> {
  final popoverController = PopoverController();

  bool isOverlayButtonsHidden = true;
  bool isPopoverOpen = false;

  @override
  Widget build(BuildContext context) {
    return UniversalPlatform.isDesktopOrWeb
        ? _buildDesktopCover()
        : _buildMobileCover();
  }

  Widget _buildDesktopCover() {
    return SizedBox(
      height: kCoverHeight,
      child: MouseRegion(
        onEnter: (event) => setOverlayButtonsHidden(false),
        onExit: (event) =>
            setOverlayButtonsHidden(isPopoverOpen ? false : true),
        child: Stack(
          children: [
            SizedBox(
              height: double.infinity,
              width: double.infinity,
              child: DesktopCover(
                view: widget.view,
                editorState: widget.editorState,
                node: widget.node,
                coverType: widget.coverType,
                coverDetails: widget.coverDetails,
              ),
            ),
            if (!isOverlayButtonsHidden) _buildCoverOverlayButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCover() {
    return SizedBox(
      height: kCoverHeight,
      child: Stack(
        children: [
          SizedBox(
            height: double.infinity,
            width: double.infinity,
            child: _buildCoverImage(),
          ),
          Positioned(
            bottom: 8,
            right: 12,
            child: Row(
              children: [
                IntrinsicWidth(
                  child: RoundedTextButton(
                    fontSize: 14,
                    onPressed: () {
                      showMobileBottomSheet(
                        context,
                        showHeader: true,
                        showDragHandle: true,
                        showCloseButton: true,
                        title:
                            LocaleKeys.document_plugins_cover_changeCover.tr(),
                        builder: (context) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 340,
                                minHeight: 80,
                              ),
                              child: UploadImageMenu(
                                limitMaximumImageSize: !_isLocalMode(),
                                supportTypes: const [
                                  UploadImageType.color,
                                  UploadImageType.local,
                                  UploadImageType.url,
                                  UploadImageType.unsplash,
                                ],
                                onSelectedLocalImages: (files) async {
                                  context.pop();

                                  if (files.isEmpty) {
                                    return;
                                  }

                                  widget.onChangeCover(
                                    CoverType.file,
                                    files.first.path,
                                  );
                                },
                                onSelectedAIImage: (_) {
                                  throw UnimplementedError();
                                },
                                onSelectedNetworkImage: (url) async {
                                  context.pop();
                                  widget.onChangeCover(CoverType.file, url);
                                },
                                onSelectedColor: (color) {
                                  context.pop();
                                  widget.onChangeCover(CoverType.color, color);
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                    fillColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.5),
                    height: 32,
                    title: LocaleKeys.document_plugins_cover_changeCover.tr(),
                  ),
                ),
                const HSpace(8.0),
                SizedBox.square(
                  dimension: 32.0,
                  child: DeleteCoverButton(
                    onTap: () => widget.onChangeCover(CoverType.none, null),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage() {
    final detail = widget.coverDetails;
    if (detail == null) {
      return const SizedBox.shrink();
    }
    switch (widget.coverType) {
      case CoverType.file:
        if (isURL(detail)) {
          final userProfilePB =
              context.read<DocumentBloc>().state.userProfilePB;
          return FlowyNetworkImage(
            url: detail,
            userProfilePB: userProfilePB,
            errorWidgetBuilder: (context, url, error) =>
                const SizedBox.shrink(),
          );
        }
        final imageFile = File(detail);
        if (!imageFile.existsSync()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onChangeCover(CoverType.none, null);
          });
          return const SizedBox.shrink();
        }
        return Image.file(
          imageFile,
          fit: BoxFit.cover,
        );
      case CoverType.asset:
        return Image.asset(
          widget.coverDetails!,
          fit: BoxFit.cover,
        );
      case CoverType.color:
        final color = widget.coverDetails?.tryToColor() ?? Colors.white;
        return Container(color: color);
      case CoverType.none:
        return const SizedBox.shrink();
    }
  }

  /// [fork:rtl] The direction the cover's overlay buttons should follow — the
  /// **page's**, not the app layout's. Same resolution the title and icon use
  /// (`_DocumentCoverWidgetState._headerDirection`), so all three agree.
  ///
  /// ⚠️ Why the ambient `Directionality` is not enough on its own: this user
  /// runs an LTR *interface* with RTL *pages*, so `Directionality.of(context)`
  /// here is LTR and both the `Row` order and the `Positioned` edge would stay
  /// pinned as if the page were LTR. It is passed in as `layoutDirection`
  /// because that is the correct fallback when a page has no direction of its
  /// own and its title gives no hint.
  ui.TextDirection _coverButtonsDirection(BuildContext context) =>
      EditorStyleCustomizer.headerTextDirection(
        defaultTextDirection:
            widget.editorState.editorStyle.defaultTextDirection,
        text: widget.view.name,
        layoutDirection: Directionality.of(context),
      );

  Widget _buildCoverOverlayButtons(BuildContext context) {
    final direction = _coverButtonsDirection(context);
    return Positioned.directional(
      // `end` rather than a hardcoded `right`: identical to before on an LTR
      // page (end == right), and moves the pair to the left edge on an RTL one.
      textDirection: direction,
      bottom: 20,
      end: 50,
      child: Directionality(
        // Flips the button ORDER — a Row lays its children out along the
        // ambient direction, so this one wrapper handles order while
        // `Positioned.directional` above handles placement.
        textDirection: direction,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFlowyPopover(
              controller: popoverController,
              triggerActions: PopoverTriggerFlags.none,
              offset: const Offset(0, 8),
              direction: PopoverDirection.bottomWithCenterAligned,
              constraints: const BoxConstraints(
                maxWidth: 540,
                maxHeight: 360,
                minHeight: 80,
              ),
              margin: EdgeInsets.zero,
              onClose: () => isPopoverOpen = false,
              child: IntrinsicWidth(
                child: RoundedTextButton(
                  height: 28.0,
                  onPressed: () => popoverController.show(),
                  hoverColor: Theme.of(context).colorScheme.surface,
                  textColor: Theme.of(context).colorScheme.tertiary,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.5),
                  title: LocaleKeys.document_plugins_cover_changeCover.tr(),
                ),
              ),
              popupBuilder: (BuildContext popoverContext) {
                isPopoverOpen = true;

                return UploadImageMenu(
                  limitMaximumImageSize: !_isLocalMode(),
                  supportTypes: const [
                    UploadImageType.color,
                    UploadImageType.local,
                    UploadImageType.url,
                    UploadImageType.unsplash,
                  ],
                  onSelectedLocalImages: (files) {
                    popoverController.close();
                    if (files.isEmpty) {
                      return;
                    }

                    final item = files.map((file) => file.path).first;
                    onCoverChanged(CoverType.file, item);
                  },
                  onSelectedAIImage: (_) {
                    throw UnimplementedError();
                  },
                  onSelectedNetworkImage: (url) {
                    popoverController.close();
                    onCoverChanged(CoverType.file, url);
                  },
                  onSelectedColor: (color) {
                    popoverController.close();
                    onCoverChanged(CoverType.color, color);
                  },
                );
              },
            ),
            const HSpace(10),
            DeleteCoverButton(
              onTap: () => onCoverChanged(CoverType.none, null),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> onCoverChanged(CoverType type, String? details) async {
    final previousType = CoverType.fromString(
      widget.node.attributes[DocumentHeaderBlockKeys.coverType],
    );
    final previousDetails =
        widget.node.attributes[DocumentHeaderBlockKeys.coverDetails];

    bool isFileType(CoverType type, String? details) =>
        type == CoverType.file && details != null && !isURL(details);

    if (isFileType(type, details)) {
      if (_isLocalMode()) {
        details = await saveImageToLocalStorage(details!);
      } else {
        // else we should save the image to cloud storage
        (details, _) = await saveImageToCloudStorage(details!, widget.view.id);
      }
    }
    widget.onChangeCover(type, details);

    // After cover change,delete from localstorage if previous cover was image type
    if (isFileType(previousType, previousDetails) && _isLocalMode()) {
      await deleteImageFromLocalStorage(previousDetails);
    }
  }

  void setOverlayButtonsHidden(bool value) {
    if (isOverlayButtonsHidden == value) return;
    setState(() {
      isOverlayButtonsHidden = value;
    });
  }

  bool _isLocalMode() {
    return context.read<DocumentBloc>().isLocalMode;
  }
}

@visibleForTesting
class DeleteCoverButton extends StatelessWidget {
  const DeleteCoverButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fillColor = UniversalPlatform.isDesktopOrWeb
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final svgColor = UniversalPlatform.isDesktopOrWeb
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onPrimary;
    return FlowyIconButton(
      hoverColor: Theme.of(context).colorScheme.surface,
      fillColor: fillColor,
      iconPadding: const EdgeInsets.all(5),
      width: 28,
      icon: FlowySvg(
        FlowySvgs.delete_s,
        color: svgColor,
      ),
      onPressed: onTap,
    );
  }
}

@visibleForTesting
class DocumentIcon extends StatefulWidget {
  const DocumentIcon({
    super.key,
    required this.node,
    required this.editorState,
    required this.icon,
    required this.onChangeIcon,
    this.documentId,
  });

  final Node node;
  final EditorState editorState;
  final EmojiIconData icon;
  final String? documentId;
  final ValueChanged<EmojiIconData> onChangeIcon;

  @override
  State<DocumentIcon> createState() => _DocumentIconState();
}

class _DocumentIconState extends State<DocumentIcon> {
  final PopoverController _popoverController = PopoverController();

  @override
  Widget build(BuildContext context) {
    Widget child = EmojiIconWidget(emoji: widget.icon);

    if (UniversalPlatform.isDesktopOrWeb) {
      child = AppFlowyPopover(
        direction: PopoverDirection.bottomWithCenterAligned,
        controller: _popoverController,
        offset: const Offset(0, 8),
        constraints: BoxConstraints.loose(const Size(360, 380)),
        margin: EdgeInsets.zero,
        child: child,
        popupBuilder: (BuildContext popoverContext) {
          return FlowyIconEmojiPicker(
            initialType: widget.icon.type.toPickerTabType(),
            tabs: const [
              PickerTabType.emoji,
              PickerTabType.icon,
              PickerTabType.custom,
            ],
            documentId: widget.documentId,
            onSelectedEmoji: (r) {
              widget.onChangeIcon(r.data);
              if (!r.keepOpen) _popoverController.close();
            },
          );
        },
      );
    } else {
      child = GestureDetector(
        child: child,
        onTap: () async {
          final result = await context.push<EmojiIconData>(
            Uri(
              path: MobileEmojiPickerScreen.routeName,
              queryParameters: {
                MobileEmojiPickerScreen.iconSelectedType: widget.icon.type.name,
              },
            ).toString(),
          );
          if (result != null) {
            widget.onChangeIcon(result);
          }
        },
      );
    }

    return child;
  }
}
