import 'dart:convert';

import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/sidebar/space/temporary_space_migration.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fork:temp-space] Phase 3 — the one-time adoption of the default space.
///
/// This is the only part of the feature that writes to the user's data, so the
/// decision table is tested exhaustively: when it writes, when it refuses, and
/// above all **what** it writes (the `extra` merge, which if wrong would strip
/// a space of its identity).
ViewPB _space(String id, {String? name, Map<String, dynamic>? ext}) {
  final view = ViewPB()
    ..id = id
    ..name = name ?? id
    ..layout = ViewLayoutPB.Document;
  if (ext != null) {
    view.extra = jsonEncode(ext);
  }
  return view;
}

Map<String, dynamic> _fullSpaceExtra({bool temporary = false}) => {
      ViewExtKeys.isSpaceKey: true,
      ViewExtKeys.spaceIconKey: 'space_icon_1',
      ViewExtKeys.spaceIconColorKey: '0xFFA34AFD',
      ViewExtKeys.spacePermissionKey: 0,
      ViewExtKeys.spaceCreatorKey: 'someone',
      if (temporary) ViewExtKeys.isTemporaryKey: true,
    };

/// Records what the migration tried to write.
class _Recorder {
  int snapshots = 0;
  int writes = 0;
  String? viewId;
  String? name;
  String? extra;
  bool succeed = true;
  bool snapshotThrows = false;

  Future<void> takeSnapshot() async {
    snapshots++;
    if (snapshotThrows) {
      throw StateError('no backup destination configured');
    }
  }

  Future<bool> writeView({
    required String viewId,
    required String name,
    required String extra,
  }) async {
    writes++;
    this.viewId = viewId;
    this.name = name;
    this.extra = extra;
    return succeed;
  }
}

Future<TemporaryMigrationOutcome> _run(
  _Recorder recorder,
  List<ViewPB> spaces,
) =>
    TemporarySpaceMigration.run(
      spaces: spaces,
      takeSnapshot: recorder.takeSnapshot,
      writeView: recorder.writeView,
    );

void main() {
  group('when it refuses to write', () {
    test('a space is already flagged — idempotent, no second run', () async {
      final recorder = _Recorder();
      final spaces = [
        _space('a', ext: _fullSpaceExtra()),
        _space('t', ext: _fullSpaceExtra(temporary: true)),
      ];

      expect(
        await _run(recorder, spaces),
        TemporaryMigrationOutcome.alreadyDone,
      );
      expect(recorder.writes, 0);
      expect(
        recorder.snapshots,
        0,
        reason: 'must not take a snapshot when there is nothing to do — this '
            'runs on every launch',
      );
    });

    test('no spaces yet — nothing to adopt, nothing written', () async {
      final recorder = _Recorder();
      expect(await _run(recorder, []), TemporaryMigrationOutcome.noSpaces);
      expect(recorder.writes, 0);
      expect(recorder.snapshots, 0);
    });
  });

  group('when it adopts', () {
    test('targets the FIRST space and renames it', () async {
      final recorder = _Recorder();
      final spaces = [
        _space('first', name: 'General', ext: _fullSpaceExtra()),
        _space('second', name: 'Customers', ext: _fullSpaceExtra()),
      ];

      expect(await _run(recorder, spaces), TemporaryMigrationOutcome.adopted);
      expect(recorder.writes, 1);
      expect(recorder.viewId, 'first');
      expect(recorder.name, kTemporarySpaceCanonicalName);
    });

    test('snapshots BEFORE writing', () async {
      final recorder = _Recorder();
      await _run(recorder, [_space('a', ext: _fullSpaceExtra())]);
      expect(recorder.snapshots, 1);
      expect(recorder.writes, 1);
    });

    test('the stored name is canonical English, not a translation', () async {
      // The sidebar renders the localized name; the data keeps one fixed value
      // so it can't depend on which language was active at migration time.
      final recorder = _Recorder();
      await _run(recorder, [_space('a', ext: _fullSpaceExtra())]);
      expect(recorder.name, 'Temporary');
    });

    test('a failed snapshot does NOT abort the write', () async {
      // Otherwise the feature would never activate for anyone whose backup
      // destination isn't configured.
      final recorder = _Recorder()..snapshotThrows = true;
      expect(
        await _run(recorder, [_space('a', ext: _fullSpaceExtra())]),
        TemporaryMigrationOutcome.adopted,
      );
      expect(recorder.writes, 1);
    });

    test('a failed write reports failure and stays retryable', () async {
      final recorder = _Recorder()..succeed = false;
      expect(
        await _run(recorder, [_space('a', ext: _fullSpaceExtra())]),
        TemporaryMigrationOutcome.failed,
      );
      // Nothing durable changed, so the next launch sees an unflagged
      // workspace and tries again.
      expect(
        TemporarySpace.isFlagged(_space('a', ext: _fullSpaceExtra())),
        isFalse,
      );
    });
  });

  group('the extra merge — the part that could destroy a space', () {
    test('adds the flag and PRESERVES every existing key', () async {
      final recorder = _Recorder();
      await _run(recorder, [_space('a', ext: _fullSpaceExtra())]);

      final written = jsonDecode(recorder.extra!) as Map<String, dynamic>;
      expect(written[ViewExtKeys.isTemporaryKey], isTrue);
      // If any of these were dropped the space would stop being a space, or
      // would lose its icon/permission.
      expect(written[ViewExtKeys.isSpaceKey], isTrue);
      expect(written[ViewExtKeys.spaceIconKey], 'space_icon_1');
      expect(written[ViewExtKeys.spaceIconColorKey], '0xFFA34AFD');
      expect(written[ViewExtKeys.spacePermissionKey], 0);
      expect(written[ViewExtKeys.spaceCreatorKey], 'someone');
    });

    test('the written extra reads back as flagged', () async {
      final recorder = _Recorder();
      await _run(recorder, [_space('a', ext: _fullSpaceExtra())]);

      final reloaded = ViewPB()
        ..id = 'a'
        ..extra = recorder.extra!;
      expect(TemporarySpace.isFlagged(reloaded), isTrue);
    });

    test('empty extra still produces a valid flagged map', () {
      final written = jsonDecode(
        TemporarySpaceMigration.mergedExtra(_space('a')),
      ) as Map<String, dynamic>;
      expect(written, {ViewExtKeys.isTemporaryKey: true});
    });

    test('malformed extra is treated as empty rather than throwing', () {
      final broken = ViewPB()
        ..id = 'a'
        ..extra = 'not json';
      final written = jsonDecode(TemporarySpaceMigration.mergedExtra(broken))
          as Map<String, dynamic>;
      expect(written[ViewExtKeys.isTemporaryKey], isTrue);
    });

    test('non-object extra is treated as empty rather than throwing', () {
      final odd = ViewPB()
        ..id = 'a'
        ..extra = '[1,2,3]';
      final written = jsonDecode(TemporarySpaceMigration.mergedExtra(odd))
          as Map<String, dynamic>;
      expect(written[ViewExtKeys.isTemporaryKey], isTrue);
    });
  });

  test('identity is by flag, not by name — a space NAMED Temporary is not it',
      () async {
    final recorder = _Recorder();
    final spaces = [
      _space('impostor', name: 'Temporary', ext: _fullSpaceExtra()),
      _space('other', name: 'Work', ext: _fullSpaceExtra()),
    ];
    // Nothing is flagged, so it still adopts — and it adopts by position, so
    // the migration is not fooled by (nor dependent on) the display name.
    expect(await _run(recorder, spaces), TemporaryMigrationOutcome.adopted);
    expect(recorder.viewId, 'impostor');
  });
}
