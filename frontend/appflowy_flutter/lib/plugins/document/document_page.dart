import 'dart:ui' as ui;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
// [fork:rtl]
import 'package:appflowy/plugins/document/application/page_text_direction.dart';
import 'package:appflowy/plugins/document/presentation/banner.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_handler.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/widgets/ai_writer_scroll_wrapper.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/document_immersive_cover.dart';
import 'package:appflowy/plugins/document/application/page_theme_mode.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_surface.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_theme_scope.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/transaction_handler/editor_transaction_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
// [fork:ribbon]
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/application/ribbon_settings_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/ribbon_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/ribbon_tabs.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/flowy_error_page.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

class DocumentPage extends StatefulWidget {
  const DocumentPage({
    super.key,
    required this.view,
    required this.onDeleted,
    required this.tabs,
    this.initialSelection,
    this.initialBlockId,
    this.fixedTitle,
  });

  final ViewPB view;
  final VoidCallback onDeleted;
  final Selection? initialSelection;
  final String? initialBlockId;
  final String? fixedTitle;
  final List<PickerTabType> tabs;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage>
    with WidgetsBindingObserver {
  EditorState? editorState;
  Selection? initialSelection;
  late final documentBloc = DocumentBloc(documentId: widget.view.id)
    ..add(const DocumentEvent.initial());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    documentBloc.close();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      documentBloc.add(const DocumentEvent.clearAwarenessStates());
    } else if (state == AppLifecycleState.resumed) {
      documentBloc.add(const DocumentEvent.syncAwarenessStates());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: getIt<ActionNavigationBloc>()),
        BlocProvider.value(value: documentBloc),
        BlocProvider(
          create: (context) =>
              ViewBloc(view: widget.view)..add(const ViewEvent.initial()),
          lazy: false,
        ),
      ],
      child: BlocConsumer<PageAccessLevelBloc, PageAccessLevelState>(
        listenWhen: (prev, curr) =>
            curr.isLocked != prev.isLocked ||
            curr.accessLevel != prev.accessLevel ||
            curr.isLoadingLockStatus != prev.isLoadingLockStatus,
        listener: (context, pageAccessLevelState) {
          if (pageAccessLevelState.isLoadingLockStatus) {
            return;
          }

          editorState?.editable = pageAccessLevelState.isEditable;
        },
        builder: (context, pageAccessLevelState) {
          return BlocBuilder<DocumentBloc, DocumentState>(
            buildWhen: shouldRebuildDocument,
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }

              final editorState = state.editorState;
              this.editorState = editorState;
              final error = state.error;
              if (error != null || editorState == null) {
                Log.error(error);
                return Center(child: AppFlowyErrorPage(error: error));
              }

              if (state.forceClose) {
                widget.onDeleted();
                return const SizedBox.shrink();
              }

              return MultiBlocListener(
                listeners: [
                  BlocListener<PageAccessLevelBloc, PageAccessLevelState>(
                    listener: (context, state) {
                      editorState.editable = state.isEditable;
                    },
                  ),
                  BlocListener<ActionNavigationBloc, ActionNavigationState>(
                    listenWhen: (_, curr) => curr.action != null,
                    listener: onNotificationAction,
                  ),
                ],
                child: AiWriterScrollWrapper(
                  viewId: widget.view.id,
                  editorState: editorState,
                  child: buildEditorPage(context, state),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget buildEditorPage(
    BuildContext context,
    DocumentState state,
  ) {
    final editorState = state.editorState;
    if (editorState == null) {
      return const SizedBox.shrink();
    }

    final width = context.read<DocumentAppearanceCubit>().state.width;

    // [fork:rtl] The page's own reading direction decides which side gets the
    // wider margin, because the block option gutter — the thing the margin has
    // to compensate for — sits on the *text's* leading side, not the app
    // layout's. Sourcing this from the layout direction (as it did before
    // Phase 2) breaks the moment the two disagree: measured on the real target,
    // an RTL page under an LTR layout rendered margins of 40 / 187 because both
    // the padding and the gutter reserved space on the same side.
    //
    // Read from the ViewBloc rather than `widget.view` so a direction change
    // from the ribbon repaints immediately instead of on next open.
    final view = context.watch<ViewBloc>().state.view;
    final pageDirection = view.pageTextDirection;
    final resolvedDirection = pageDirection.editorValue ??
        context.read<DocumentAppearanceCubit>().state.defaultTextDirection;

    final documentPadding = EditorStyleCustomizer.documentPaddingFor(
      switch (resolvedDirection) {
        'rtl' => ui.TextDirection.rtl,
        'ltr' => ui.TextDirection.ltr,
        // 'auto' (and anything unrecognised) has no single answer at page
        // level — each block decides for itself — so fall back to the app
        // layout, which is what the surrounding Directionality uses.
        _ => context.read<AppearanceSettingsCubit>().state.layoutDirection ==
                LayoutDirection.rtlLayout
            ? ui.TextDirection.rtl
            : ui.TextDirection.ltr,
      },
    );

    // avoid the initial selection calculation change when the editorState is not changed
    initialSelection ??= _calculateInitialSelection(editorState);

    // [fork:page-surface] Built as a closure of `ctx`, not eagerly, so that on
    // desktop it is built INSIDE PageThemeScope — the EditorStyleCustomizer and
    // the cover/title then resolve every theme colour (text, links, code, …)
    // from the PAGE's theme, not the app layout's. Otherwise a page overridden
    // to a different brightness kept the layout's text/link colours and lost
    // contrast (dark text on a dark page, and vice versa). Mobile has no
    // PageThemeScope, so it just gets the outer context.
    Widget buildEditorContent(BuildContext ctx) {
      if (UniversalPlatform.isMobile) {
        return BlocBuilder<DocumentPageStyleBloc, DocumentPageStyleState>(
          builder: (context, styleState) => AppFlowyEditorPage(
            editorState: editorState,
            // if the view's name is empty, focus on the title
            autoFocus: widget.view.name.isEmpty ? false : null,
            styleCustomizer: EditorStyleCustomizer(
              context: context,
              width: width,
              padding: documentPadding,
              editorState: editorState,
              pageTextDirection: pageDirection.editorValue,
            ),
            header: buildCoverAndIcon(context, state),
            initialSelection: initialSelection,
          ),
        );
      }
      return EditorDropHandler(
        viewId: widget.view.id,
        editorState: editorState,
        isLocalMode: ctx.read<DocumentBloc>().isLocalMode,
        child: AppFlowyEditorPage(
          editorState: editorState,
          // if the view's name is empty, focus on the title
          autoFocus: widget.view.name.isEmpty ? false : null,
          styleCustomizer: EditorStyleCustomizer(
            context: ctx,
            width: width,
            padding: documentPadding,
            editorState: editorState,
            pageTextDirection: pageDirection.editorValue,
          ),
          header: buildCoverAndIcon(ctx, state),
          initialSelection: initialSelection,
          placeholderText: (node) =>
              node.type == ParagraphBlockKeys.type && !node.isInTable
                  ? LocaleKeys.editor_slashPlaceHolder.tr()
                  : '',
        ),
      );
    }

    return Provider(
      create: (_) {
        final context = SharedEditorContext();
        final children = editorState.document.root.children;
        final firstDelta = children.firstOrNull?.delta;
        final isEmptyDocument =
            children.length == 1 && (firstDelta == null || firstDelta.isEmpty);
        if (widget.view.name.isEmpty && isEmptyDocument) {
          context.requestCoverTitleFocus = true;
        }
        return context;
      },
      dispose: (buildContext, editorContext) => editorContext.dispose(),
      child: EditorTransactionService(
        viewId: widget.view.id,
        editorState: state.editorState!,
        child: Column(
          children: [
            // the banner only shows on desktop
            if (state.isDeleted && UniversalPlatform.isDesktop)
              buildBanner(context),
            // [fork:ribbon] Pinned formatting strip (specs/ribbon-menu.md).
            // Mounted here, as a sibling above the editor, rather than via the
            // editor's `header:` param — a header scrolls away with the
            // document, and the ribbon must stay put.
            if (FeatureFlag.ribbonMenu.isOn && UniversalPlatform.isDesktop)
              BlocProvider.value(
                value: getIt<RibbonSettingsCubit>(),
                child: RibbonMenu(
                  editorState: editorState,
                  tabs: buildRibbonTabs(),
                ),
              ),
            // [fork:page-surface] Wraps only the editor area, so the ribbon
            // above keeps sitting on the app layout rather than on the page.
            // The width is the document column's own, so the sheet lines up
            // with the text on it. PageThemeScope applies this page's own
            // light/dark override (set from the ribbon) to just this subtree;
            // it is a no-op when the page inherits the app theme
            // (page_theme_mode.dart).
            Expanded(
              child: UniversalPlatform.isDesktop
                  ? PageThemeScope(
                      pageThemeMode: view.pageThemeMode,
                      child: PageSurface(
                        pageWidth:
                            context.read<DocumentAppearanceCubit>().state.width,
                        // Builder so the editor is built under the page theme.
                        child: Builder(builder: buildEditorContent),
                      ),
                    )
                  : buildEditorContent(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBanner(BuildContext context) {
    return DocumentBanner(
      viewName: widget.view.nameOrDefault,
      onRestore: () =>
          context.read<DocumentBloc>().add(const DocumentEvent.restorePage()),
      onDelete: () => context
          .read<DocumentBloc>()
          .add(const DocumentEvent.deletePermanently()),
    );
  }

  Widget buildCoverAndIcon(BuildContext context, DocumentState state) {
    final editorState = state.editorState;
    final userProfilePB = state.userProfilePB;
    if (editorState == null || userProfilePB == null) {
      return const SizedBox.shrink();
    }

    if (UniversalPlatform.isMobile) {
      return DocumentImmersiveCover(
        fixedTitle: widget.fixedTitle,
        view: widget.view,
        tabs: widget.tabs,
        userProfilePB: userProfilePB,
      );
    }

    final page = editorState.document.root;
    return DocumentCoverWidget(
      node: page,
      tabs: widget.tabs,
      editorState: editorState,
      view: widget.view,
      onIconChanged: (icon) async => ViewBackendService.updateViewIcon(
        view: widget.view,
        viewIcon: icon,
      ),
    );
  }

  void onNotificationAction(
    BuildContext context,
    ActionNavigationState state,
  ) {
    final action = state.action;
    if (action == null ||
        action.type != ActionType.jumpToBlock ||
        action.objectId != widget.view.id) {
      return;
    }

    final editorState = context.read<DocumentBloc>().state.editorState;
    if (editorState == null) {
      return;
    }

    final Path? path = _getPathFromAction(action, editorState);
    if (path != null) {
      editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: path)),
      );
    }
  }

  Path? _getPathFromAction(NavigationAction action, EditorState editorState) {
    final path = action.arguments?[ActionArgumentKeys.nodePath];
    if (path is int) {
      return [path];
    } else if (path is List<int>?) {
      if (path == null || path.isEmpty) {
        final blockId = action.arguments?[ActionArgumentKeys.blockId];
        if (blockId != null) {
          return _findNodePathByBlockId(editorState, blockId);
        }
      }
    }
    return path;
  }

  Path? _findNodePathByBlockId(EditorState editorState, String blockId) {
    final document = editorState.document;
    final startNode = document.root.children.firstOrNull;
    if (startNode == null) {
      return null;
    }

    final nodeIterator = NodeIterator(document: document, startNode: startNode);
    while (nodeIterator.moveNext()) {
      final node = nodeIterator.current;
      if (node.id == blockId) {
        return node.path;
      }
    }

    return null;
  }

  bool shouldRebuildDocument(DocumentState previous, DocumentState current) {
    // only rebuild the document page when the below fields are changed
    // this is to prevent unnecessary rebuilds
    //
    // If you confirm the newly added fields should be rebuilt, please update
    // this function.
    if (previous.editorState != current.editorState) {
      return true;
    }

    if (previous.forceClose != current.forceClose ||
        previous.isDeleted != current.isDeleted) {
      return true;
    }

    if (previous.userProfilePB != current.userProfilePB) {
      return true;
    }

    if (previous.isLoading != current.isLoading ||
        previous.error != current.error) {
      return true;
    }

    return false;
  }

  Selection? _calculateInitialSelection(EditorState editorState) {
    if (widget.initialSelection != null) {
      return widget.initialSelection;
    }

    if (widget.initialBlockId != null) {
      final path = _findNodePathByBlockId(editorState, widget.initialBlockId!);
      if (path != null) {
        editorState.selectionType = SelectionType.block;
        editorState.selectionExtraInfo = {
          selectionExtraInfoDoNotAttachTextService: true,
        };
        return Selection.collapsed(
          Position(
            path: path,
          ),
        );
      }
    }

    return null;
  }
}
