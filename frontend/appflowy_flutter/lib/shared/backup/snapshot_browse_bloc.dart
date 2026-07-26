import 'package:appflowy_backend/log.dart';
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

  List<SnapshotNode> _visible() =>
      state.showOnlyMissing ? filterToMissing(_fullTree) : _fullTree;
}
