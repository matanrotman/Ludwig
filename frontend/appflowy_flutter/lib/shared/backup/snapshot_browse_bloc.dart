import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:bloc/bloc.dart';

import 'snapshot_browse_model.dart';
import 'snapshot_browse_service.dart';
import 'snapshot_repository.dart';

/// State of the restore browser (`specs/restore-redesign.md` Phase 1).
///
/// Phase 1 browses only — there is no selection and no merge here yet, by design
/// (D8: the write step happens on relaunch, never beside a live editor).
class SnapshotBrowseState {
  const SnapshotBrowseState({
    this.days = const [],
    this.selected,
    this.tree = const [],
    this.showOnlyMissing = false,
    this.isLoadingDays = true,
    this.isLoadingTree = false,
    this.error,
    this.comparisonUnavailable = false,
    this.previewNode,
    this.preview,
    this.isLoadingPreview = false,
    this.previewError,
  });

  final List<SnapshotDay> days;

  /// The snapshot currently open, if any.
  final SnapshotInfo? selected;

  /// The tree of [selected], already filtered by [showOnlyMissing].
  final List<SnapshotNode> tree;

  final bool showOnlyMissing;
  final bool isLoadingDays;
  final bool isLoadingTree;
  final String? error;

  /// True when the live workspace couldn't be read, so "missing" is unknowable.
  /// The UI must then hide the missing markers rather than show them all as absent.
  final bool comparisonUnavailable;

  /// The page being previewed (D5), if one was clicked.
  final SnapshotNode? previewNode;

  /// That page's content out of the snapshot. Null while loading or on failure.
  final DocumentDataPB? preview;

  final bool isLoadingPreview;

  /// A preview-only failure. Kept apart from [error] so a page that can't be
  /// read doesn't blank out the tree that is still perfectly readable.
  final String? previewError;

  SnapshotBrowseState copyWith({
    List<SnapshotDay>? days,
    SnapshotInfo? selected,
    List<SnapshotNode>? tree,
    bool? showOnlyMissing,
    bool? isLoadingDays,
    bool? isLoadingTree,
    String? error,
    bool? comparisonUnavailable,
    bool clearError = false,
    SnapshotNode? previewNode,
    DocumentDataPB? preview,
    bool? isLoadingPreview,
    String? previewError,
    bool clearPreview = false,
  }) =>
      SnapshotBrowseState(
        days: days ?? this.days,
        selected: selected ?? this.selected,
        tree: tree ?? this.tree,
        showOnlyMissing: showOnlyMissing ?? this.showOnlyMissing,
        isLoadingDays: isLoadingDays ?? this.isLoadingDays,
        isLoadingTree: isLoadingTree ?? this.isLoadingTree,
        error: clearError ? null : (error ?? this.error),
        comparisonUnavailable:
            comparisonUnavailable ?? this.comparisonUnavailable,
        // The preview fields clear together or not at all: a half-cleared
        // preview would show one page's title over another page's content.
        previewNode: clearPreview ? null : (previewNode ?? this.previewNode),
        preview: clearPreview ? null : (preview ?? this.preview),
        isLoadingPreview: clearPreview ? false : (isLoadingPreview ?? this.isLoadingPreview),
        previewError: clearPreview ? null : (previewError ?? this.previewError),
      );
}

class SnapshotBrowseBloc extends Cubit<SnapshotBrowseState> {
  SnapshotBrowseBloc({
    required this.destinationPath,
    required this.repository,
    this.service = const SnapshotBrowseService(),
  }) : super(const SnapshotBrowseState());

  final String destinationPath;
  final SnapshotRepository repository;
  final SnapshotBrowseService service;

  /// The unfiltered tree, kept so toggling the filter doesn't re-read the snapshot.
  List<SnapshotNode> _fullTree = const [];

  Future<void> loadDays() async {
    emit(state.copyWith(isLoadingDays: true, clearError: true));
    try {
      final snapshots = await repository.list(destinationPath);
      emit(
        state.copyWith(
          days: groupByDay(snapshots),
          isLoadingDays: false,
        ),
      );
    } catch (e) {
      Log.error('[snapshot-browse] could not list snapshots: $e');
      emit(
        state.copyWith(
          isLoadingDays: false,
          error: 'Could not read the backup folder.',
        ),
      );
    }
  }

  Future<void> open(SnapshotInfo snapshot) async {
    emit(
      state.copyWith(
        selected: snapshot,
        isLoadingTree: true,
        tree: const [],
        clearError: true,
        // A preview belongs to the snapshot it came out of. Switching backups
        // without this would leave yesterday's version of a page on screen
        // beside today's tree — the one confusion this whole screen exists to
        // prevent.
        clearPreview: true,
      ),
    );

    final path = repository
        .snapshotsDir(destinationPath)
        .childFile(snapshot.fileName)
        .path;
    final live = await service.liveViewIds();
    final result = await service.readTree(path);

    result.fold(
      (treePB) {
        _fullTree = buildTree(
          workspaceId: treePB.workspaceId,
          views: treePB.views,
          // With no live comparison, treat everything as present so nothing is
          // falsely flagged as lost.
          liveViewIds: live ?? treePB.views.map((v) => v.id).toSet(),
        );
        emit(
          state.copyWith(
            isLoadingTree: false,
            tree: _visible(),
            comparisonUnavailable: live == null,
          ),
        );
      },
      (error) {
        Log.error('[snapshot-browse] could not read $path: ${error.msg}');
        _fullTree = const [];
        emit(
          state.copyWith(
            isLoadingTree: false,
            tree: const [],
            error: error.msg,
          ),
        );
      },
    );
  }

  void toggleMissingOnly() {
    emit(state.copyWith(showOnlyMissing: !state.showOnlyMissing));
    emit(state.copyWith(tree: _visible()));
  }

  /// Show one page from the open snapshot, read-only (D5).
  ///
  /// Containers have no document of their own, so clicking one clears the
  /// preview instead of erroring — a space is structure, and saying "this page
  /// couldn't be read" about it would be a lie.
  Future<void> preview(SnapshotNode node) async {
    final snapshot = state.selected;
    if (snapshot == null) {
      return;
    }
    if (node.isContainer) {
      emit(state.copyWith(clearPreview: true));
      return;
    }

    // Clear first, then set the node: without the clear, the previous page's
    // content stays on screen under the new page's name while this loads.
    emit(state.copyWith(clearPreview: true));
    emit(state.copyWith(previewNode: node, isLoadingPreview: true));

    final path = repository
        .snapshotsDir(destinationPath)
        .childFile(snapshot.fileName)
        .path;
    final result = await service.readDocument(path, node.id);

    // The user can click a second page while the first is still loading. Drop
    // a result that is no longer the one being asked for, rather than painting
    // the wrong page's content under the right page's name.
    if (isClosed || state.previewNode?.id != node.id) {
      return;
    }

    result.fold(
      (data) => emit(state.copyWith(preview: data, isLoadingPreview: false)),
      (error) {
        Log.error('[snapshot-browse] could not read ${node.id}: ${error.msg}');
        emit(
          state.copyWith(
            isLoadingPreview: false,
            previewError: 'This page could not be read from the backup.',
          ),
        );
      },
    );
  }

  void closePreview() => emit(state.copyWith(clearPreview: true));

  List<SnapshotNode> _visible() =>
      state.showOnlyMissing ? filterToMissing(_fullTree) : _fullTree;
}
