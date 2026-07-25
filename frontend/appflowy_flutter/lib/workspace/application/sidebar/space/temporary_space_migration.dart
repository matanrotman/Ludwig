import 'dart:convert';

import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';

/// The stored name given to the adopted space.
///
/// Deliberately **not** localized: this is the canonical value written to the
/// user's data once, whereas what the sidebar shows is the translated
/// `space.temporaryName`. Storing a translation would mean the name in the data
/// depended on which language happened to be active at migration time.
const kTemporarySpaceCanonicalName = 'Temporary';

/// What [TemporarySpaceMigration.run] did.
enum TemporaryMigrationOutcome {
  /// A space already carries the flag — nothing to do. The normal case on
  /// every launch after the first.
  alreadyDone,

  /// There are no spaces to adopt yet (a brand-new workspace, before upstream
  /// has created its starter space). Nothing written; retried next launch.
  noSpaces,

  /// The default space was renamed and flagged. Happens exactly once.
  adopted,

  /// The write failed. Nothing durable changed; retried next launch.
  failed,
}

/// [fork:temp-space] Phase 3 — the one-time adoption of the workspace's default
/// space as Temporary. See `specs/temp-space.md`.
///
/// This is the **only** part of the Temporary feature that writes to the user's
/// data, and what it writes is deliberately tiny: one view's `name`, plus one
/// key merged into that view's `extra`. No page moves, no deletions, no content.
///
/// ## Three safety properties, each load-bearing
///
/// **Idempotent — the flag is the marker.** If any space is already flagged
/// this is a no-op. There is deliberately no separate "migration done" pref: a
/// marker stored apart from the thing it describes can disagree with it (and
/// this project has already been bitten by exactly that class of drift with the
/// editor pin). Asking the data is always right.
///
/// **Identified by role, never by name.** The target is the workspace's first
/// space. A fresh AppFlowy install calls its first space `Shared`; this user's
/// is called `General`. Matching either string would be a hardcoded personal
/// value that silently does nothing for everybody else.
///
/// **Fail-soft.** No spaces, a failed write, malformed `extra` — every path
/// leaves the workspace untouched and returns rather than throwing. A workspace
/// with no flagged space still works, because [TemporarySpace.resolve] falls
/// back to treating the first space as Temporary.
///
/// The backend and the backup service are injected so the whole decision table
/// is unit-testable without a running app.
class TemporarySpaceMigration {
  const TemporarySpaceMigration._();

  static Future<TemporaryMigrationOutcome> run({
    required List<ViewPB> spaces,
    required Future<void> Function() takeSnapshot,
    required Future<bool> Function({
      required String viewId,
      required String name,
      required String extra,
    }) writeView,
    String canonicalName = kTemporarySpaceCanonicalName,
  }) async {
    if (spaces.any(TemporarySpace.isFlagged)) {
      return TemporaryMigrationOutcome.alreadyDone;
    }
    if (spaces.isEmpty) {
      // A brand-new workspace: upstream has not created its starter space yet.
      // Nothing to adopt, so wait for a later launch rather than inventing a
      // space here (see the spec's fresh-install follow-up).
      return TemporaryMigrationOutcome.noSpaces;
    }

    final target = spaces.first;

    // A snapshot before the write, on a best-effort basis.
    //
    // ⚠️ A failed snapshot deliberately does NOT abort the migration. Making
    // the snapshot a precondition would mean the feature never activates for
    // anyone whose backup destination isn't configured — and what follows is a
    // two-field metadata write on a single view, not a destructive operation.
    try {
      await takeSnapshot();
    } catch (error) {
      Log.warn('temp-space: pre-migration snapshot failed, continuing: $error');
    }

    final ok = await writeView(
      viewId: target.id,
      name: canonicalName,
      extra: mergedExtra(target),
    );
    if (!ok) {
      return TemporaryMigrationOutcome.failed;
    }
    Log.info(
      'temp-space: adopted "${target.name}"(${target.id}) as Temporary',
    );
    return TemporaryMigrationOutcome.adopted;
  }

  /// [space]'s `extra` with the Temporary flag added, **merged** into whatever
  /// is already there.
  ///
  /// Merging is not optional: a space's `extra` also carries `is_space`, its
  /// icon, its icon colour, its permission and its creator. Replacing the map
  /// would silently strip the space's identity and leave it looking like an
  /// ordinary page. Uses the same `mergeMaps` convention as `SpaceBloc.update`.
  ///
  /// Malformed or non-object `extra` is treated as empty rather than throwing —
  /// `extra` is free-form JSON written by several independent features.
  static String mergedExtra(ViewPB space) {
    var current = <String, dynamic>{};
    try {
      if (space.extra.isNotEmpty) {
        final decoded = jsonDecode(space.extra);
        if (decoded is Map<String, dynamic>) {
          current = decoded;
        }
      }
    } catch (error) {
      Log.warn('temp-space: unreadable extra on ${space.id}: $error');
    }
    return jsonEncode(
      mergeMaps(current, {ViewExtKeys.isTemporaryKey: true}),
    );
  }
}
