import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-snapshot/entities.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// Reads snapshots for the restore browser (`specs/restore-redesign.md` Phase 1).
///
/// Read-only by construction: the only backend call it makes is
/// `ReadSnapshotTree`, which opens a snapshot's database read-only and never
/// touches the live workspace.
class SnapshotBrowseService {
  const SnapshotBrowseService();

  /// The view tree inside one snapshot zip.
  Future<FlowyResult<SnapshotTreePB, FlowyError>> readTree(String zipPath) =>
      SnapshotEventReadSnapshotTree(
        ReadSnapshotTreePayloadPB(zipPath: zipPath),
      ).send();

  /// Every view id currently visible in the workspace, used to work out what a
  /// snapshot has that the live workspace doesn't (decision D6).
  ///
  /// **Known limitation, deliberate for Phase 1:** `GetAllViews` filters out
  /// trashed views, so a page sitting in the trash reads as "missing" here. That
  /// over-reports rather than under-reports — it points you at a page you really
  /// don't have in the sidebar — but the shorter route for that page is the trash,
  /// not a restore. Worth revisiting alongside the trash redesign
  /// (`specs/delete-and-trash.md`).
  ///
  /// Returns null when the live workspace can't be read: an empty set would mark
  /// *everything* in the snapshot as missing, which is a far more alarming lie
  /// than admitting the comparison failed.
  Future<Set<String>?> liveViewIds() async {
    final views = await ViewBackendService.getAllViews();
    return views.fold(
      (views) => views.items.map((view) => view.id).toSet(),
      (_) => null,
    );
  }
}
