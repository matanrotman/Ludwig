import 'dart:convert';

import 'package:appflowy/shared/backup/workspace_path_resolver.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/data/data_dev';
  const url = 'https://beta.appflowy.cloud';

  group('WorkspacePathResolver', () {
    test('prefers the base64-url folder when it exists (Rust order)',
        () async {
      final fs = MemoryFileSystem.test();
      final b64 = base64Url.encode(utf8.encode(url));
      fs.directory('${root}_$b64').createSync(recursive: true);
      fs.directory('${root}_beta.appflowy.cloud').createSync(recursive: true);

      final resolved = await WorkspacePathResolver(
        fs,
        dataRootPath: root,
        cloudBaseUrl: url,
      ).resolve();
      expect(resolved!.path, '${root}_$b64');
    });

    test('falls back to the domain-suffix folder', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('${root}_beta.appflowy.cloud').createSync(recursive: true);

      final resolved = await WorkspacePathResolver(
        fs,
        dataRootPath: root,
        cloudBaseUrl: url,
      ).resolve();
      expect(resolved!.path, '${root}_beta.appflowy.cloud');
    });

    test('anonymous then bare root when no cloud folder exists', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('${root}_anonymous').createSync(recursive: true);
      final anon = await WorkspacePathResolver(
        fs,
        dataRootPath: root,
        cloudBaseUrl: null,
      ).resolve();
      expect(anon!.path, '${root}_anonymous');

      final fs2 = MemoryFileSystem.test();
      fs2.directory(root).createSync(recursive: true);
      final bare = await WorkspacePathResolver(
        fs2,
        dataRootPath: root,
        cloudBaseUrl: null,
      ).resolve();
      expect(bare!.path, root);
    });

    test('restore artifacts are never candidates', () async {
      final fs = MemoryFileSystem.test();
      fs
          .directory('${root}_beta.appflowy.cloud.pre-restore-20260716')
          .createSync(recursive: true);
      fs
          .directory('${root}_beta.appflowy.cloud.restore-staging-20260716')
          .createSync(recursive: true);

      final resolved = await WorkspacePathResolver(
        fs,
        dataRootPath: root,
        cloudBaseUrl: url,
      ).resolve();
      expect(resolved, isNull);
    });

    test('glob fallback picks the newest sibling', () async {
      final fs = MemoryFileSystem.test();
      final old = fs.directory('${root}_old.server')
        ..createSync(recursive: true);
      final fresh = fs.directory('${root}_new.server')
        ..createSync(recursive: true);
      // MemoryFileSystem tracks mtimes on directory contents; touch files.
      old.childFile('x').writeAsStringSync('x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fresh.childFile('x').writeAsStringSync('x');

      final resolved = await WorkspacePathResolver(
        fs,
        dataRootPath: root,
        cloudBaseUrl: 'https://gone.example.com',
      ).resolve();
      expect(resolved, isNotNull);
      expect(resolved!.path, isNot(contains('pre-restore')));
    });
  });
}
