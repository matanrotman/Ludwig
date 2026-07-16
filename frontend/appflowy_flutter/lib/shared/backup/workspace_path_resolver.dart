import 'dart:convert';

import 'package:file/file.dart';

/// Resolves the LIVE workspace data folder — the one the running app is
/// actually writing to.
///
/// Dart controls only the data ROOT (e.g. `…/data_dev`); the Rust side
/// appends a per-server suffix (`flowy-core/src/config.rs::make_user_data_folder`):
///   1. `{root}_{base64url(base_url)}` if that folder already exists,
///   2. else `{root}_{host of base_url}` (the scheme since 0.8.9),
///   3. `{root}_anonymous` when there is no cloud config,
///   4. bare `{root}` for pure-local setups.
/// This resolver mirrors that preference order with existence checks rather
/// than re-deriving Rust's logic blindly, and falls back to globbing sibling
/// folders by newest content when nothing matches (config may have changed
/// between runs).
///
/// Restore artifacts (`<name>.pre-restore-*`, `<name>.restore-staging-*`)
/// are never candidates, so a crashed restore cannot confuse resolution.
class WorkspacePathResolver {
  WorkspacePathResolver(
    this.fileSystem, {
    required this.dataRootPath,
    required this.cloudBaseUrl,
  });

  final FileSystem fileSystem;

  /// From `ApplicationDataStorage.getPath()`.
  final String dataRootPath;

  /// From `AppFlowyCloudSharedEnv.appflowyCloudConfig.base_url`; null/empty
  /// for local-only mode.
  final String? cloudBaseUrl;

  static final RegExp _restoreArtifact =
      RegExp(r'\.(pre-restore|restore-staging)-');

  bool _isCandidate(String name) => !_restoreArtifact.hasMatch(name);

  Future<Directory?> resolve() async {
    final candidates = <String>[];

    final url = cloudBaseUrl;
    if (url != null && url.isNotEmpty) {
      // Rust's order: base64 folder wins if it exists, else domain suffix.
      final b64 = base64Url.encode(utf8.encode(url));
      candidates.add('${dataRootPath}_$b64');
      final host = Uri.tryParse(url)?.host;
      if (host != null && host.isNotEmpty) {
        candidates.add('${dataRootPath}_$host');
      }
    }
    candidates.add('${dataRootPath}_anonymous');
    candidates.add(dataRootPath);

    for (final path in candidates) {
      final dir = fileSystem.directory(path);
      final name = fileSystem.path.basename(path);
      if (_isCandidate(name) && await dir.exists()) {
        return dir;
      }
    }

    return _globFallback();
  }

  /// Last resort: any sibling `“<rootName>_*”` folder, newest mtime wins.
  Future<Directory?> _globFallback() async {
    final parent = fileSystem.directory(fileSystem.path.dirname(dataRootPath));
    final rootName = fileSystem.path.basename(dataRootPath);
    if (!await parent.exists()) {
      return null;
    }

    Directory? best;
    DateTime bestMtime = DateTime.fromMillisecondsSinceEpoch(0);
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = fileSystem.path.basename(entity.path);
      if (!name.startsWith('${rootName}_') || !_isCandidate(name)) {
        continue;
      }
      try {
        final mtime = (await entity.stat()).modified;
        if (mtime.isAfter(bestMtime)) {
          bestMtime = mtime;
          best = entity;
        }
      } catch (_) {}
    }
    return best;
  }
}
