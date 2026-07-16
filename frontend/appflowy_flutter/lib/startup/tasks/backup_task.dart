import 'dart:async';
import 'dart:ui';

import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_platform/universal_platform.dart';

import '../startup.dart';

/// Starts the automatic-backup service and owns the two moments the service
/// cannot see on its own:
///
/// - **Quit** (Cmd+Q): registers an [AppLifecycleListener] with
///   `onExitRequested` — the app's only Dart code that runs on a real quit
///   (`LaunchTask.dispose` fires solely on in-app restart). The handler is
///   hard-capped at 5 seconds and ALWAYS allows the exit afterwards; a hung
///   backup must never hold the app hostage. Note the window close button
///   doesn't quit this app (`applicationShouldTerminateAfterLastWindowClosed
///   → false`), so the timer keeps covering a closed-window session.
/// - **Catch-up**: ~60s after launch, one change-checked run covers whatever
///   the previous session's quit hook may have missed (crash, kill -9,
///   timeout). This backstop is what makes quit-hook failure non-fatal.
class BackupLaunchTask extends LaunchTask {
  const BackupLaunchTask();

  static const _quitBackupTimeout = Duration(seconds: 5);
  static const _catchUpDelay = Duration(seconds: 60);

  static AppLifecycleListener? _lifecycleListener;
  static Timer? _catchUpTimer;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    if (!UniversalPlatform.isDesktop) {
      return;
    }

    final service = context.getIt<BackupService>();
    await service.start();

    _lifecycleListener?.dispose();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () => _backupBeforeExit(service),
    );

    _catchUpTimer?.cancel();
    _catchUpTimer = Timer(_catchUpDelay, () {
      unawaited(service.backupNow(trigger: BackupTrigger.catchUp));
    });
  }

  @override
  Future<void> dispose() async {
    await super.dispose();

    _catchUpTimer?.cancel();
    _catchUpTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await getIt<BackupService>().stop();
  }

  Future<AppExitResponse> _backupBeforeExit(BackupService service) async {
    // A restore swap must never be interrupted by an exit; this is the ONLY
    // case that cancels a quit.
    if (service.isPaused) {
      Log.info('[Backup] exit requested during restore — cancelling exit');
      return AppExitResponse.cancel;
    }
    try {
      await service
          .backupNow(trigger: BackupTrigger.quit)
          .timeout(_quitBackupTimeout);
    } catch (e) {
      // Timeout or failure: the catch-up run next launch covers this tail.
      Log.error('[Backup] quit-time backup did not complete: $e');
    }
    return AppExitResponse.exit;
  }
}
