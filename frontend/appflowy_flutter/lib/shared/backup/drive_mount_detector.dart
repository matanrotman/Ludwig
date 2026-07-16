import 'package:file/file.dart';

/// Where a detected destination came from — the settings page shows a
/// "Google Drive detected" badge only for a real mount.
enum BackupDestinationSource { googleDriveMount, legacyDriveFolder, manual }

class DetectedDestination {
  const DetectedDestination({required this.path, required this.source});

  final String path;
  final BackupDestinationSource source;
}

/// Finds the user's Google Drive folder on macOS with no Google API involved:
/// Google Drive for desktop mounts under `~/Library/CloudStorage/`.
///
/// Preference order:
/// 1. `~/Library/CloudStorage/GoogleDrive-<account>/My Drive` — the writable
///    area of a modern Drive mount. If the localized volume uses a different
///    name for it, fall back to the mount's first writable child directory.
/// 2. `~/Google Drive` — the legacy mount location.
/// The returned destination is an `AppFlowy Backups` folder INSIDE that area
/// (created by the service on first use), so snapshots never sit unbranded
/// at the user's Drive root. Returns null when nothing is found; the service
/// then idles with a "no destination" status instead of guessing.
class DriveMountDetector {
  DriveMountDetector(this.fileSystem, {required this.homePath});

  final FileSystem fileSystem;
  final String homePath;

  static const _cloudStorage = 'Library/CloudStorage';
  static const _mountPrefix = 'GoogleDrive-';
  static const _myDrive = 'My Drive';
  static const backupsFolderName = 'AppFlowy Backups';

  String _backupsIn(String parent) =>
      fileSystem.path.join(parent, backupsFolderName);

  Future<DetectedDestination?> detect() async {
    final cloudStorage = fileSystem.directory(
      fileSystem.path.join(homePath, _cloudStorage),
    );
    if (await cloudStorage.exists()) {
      await for (final entity in cloudStorage.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (!name.startsWith(_mountPrefix)) {
          continue;
        }
        final myDrive = entity.childDirectory(_myDrive);
        if (await myDrive.exists()) {
          return DetectedDestination(
            path: _backupsIn(myDrive.path),
            source: BackupDestinationSource.googleDriveMount,
          );
        }
        // Localized "My Drive" name: take the first child directory.
        await for (final child in entity.list(followLinks: false)) {
          if (child is Directory) {
            return DetectedDestination(
              path: _backupsIn(child.path),
              source: BackupDestinationSource.googleDriveMount,
            );
          }
        }
      }
    }

    final legacy = fileSystem.directory(
      fileSystem.path.join(homePath, 'Google Drive'),
    );
    if (await legacy.exists()) {
      return DetectedDestination(
        path: _backupsIn(legacy.path),
        source: BackupDestinationSource.legacyDriveFolder,
      );
    }

    return null;
  }
}
