import 'package:appflowy/shared/backup/drive_mount_detector.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriveMountDetector', () {
    test('modern mount -> AppFlowy Backups inside My Drive', () async {
      final fs = MemoryFileSystem.test();
      fs
          .directory(
            '/home/Library/CloudStorage/GoogleDrive-me@x.com/My Drive',
          )
          .createSync(recursive: true);

      final detected = await DriveMountDetector(fs, homePath: '/home').detect();
      expect(detected, isNotNull);
      expect(detected!.source, BackupDestinationSource.googleDriveMount);
      expect(
        detected.path,
        '/home/Library/CloudStorage/GoogleDrive-me@x.com/My Drive/AppFlowy Backups',
      );
    });

    test('localized volume name -> first child directory', () async {
      final fs = MemoryFileSystem.test();
      fs
          .directory(
            '/home/Library/CloudStorage/GoogleDrive-me@x.com/Mon Drive',
          )
          .createSync(recursive: true);

      final detected = await DriveMountDetector(fs, homePath: '/home').detect();
      expect(detected, isNotNull);
      expect(detected!.path, endsWith('Mon Drive/AppFlowy Backups'));
    });

    test('legacy ~/Google Drive fallback', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/home/Google Drive').createSync(recursive: true);

      final detected = await DriveMountDetector(fs, homePath: '/home').detect();
      expect(detected, isNotNull);
      expect(detected!.source, BackupDestinationSource.legacyDriveFolder);
      expect(detected.path, '/home/Google Drive/AppFlowy Backups');
    });

    test('nothing found -> null (service idles, never guesses)', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/home').createSync(recursive: true);
      expect(
        await DriveMountDetector(fs, homePath: '/home').detect(),
        isNull,
      );
    });
  });
}
