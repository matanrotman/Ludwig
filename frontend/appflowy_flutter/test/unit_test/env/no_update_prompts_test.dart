import 'package:appflowy/env/ludwig_update_policy.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ludwig never invites anyone to update. `specs/distribution.md`, session 18.
///
/// **Why this file is worth its weight.** Upstream's updater points at
/// AppFlowy's GitHub releases, so a fresh Ludwig install showed *"New Version
/// (0.13.0) Available! Current version: 0.11.4 (Official build)"* with a
/// working Update button — Ludwig inviting its own users to replace it with
/// AppFlowy. That was found by a live fresh-install drill, not by a test,
/// because it only appears on a genuinely clean launch.
///
/// These tests cannot re-create that launch. What they *can* do is hold the
/// gate shut: `isUpdateAvailable` is the single property both update surfaces
/// read (the sidebar banner and the Settings row), so if it stays false with a
/// newer version in hand, neither can appear.
void main() {
  group('Ludwig update policy', () {
    test('updates are off and the feed is still a placeholder', () {
      expect(LudwigUpdatePolicy.checkForUpdates, isFalse);
      // If this ever holds a URL, it must be Ludwig's own — never AppFlowy's.
      // `AutoUpdateTask` asserts on the same pairing at runtime.
      expect(LudwigUpdatePolicy.feedUrl, isNull);
    });
  });

  group('ApplicationInfo.isUpdateAvailable', () {
    tearDown(() {
      ApplicationInfo.applicationVersion = '';
      ApplicationInfo.latestVersionNotifier.value = '';
    });

    test('stays false even when a much newer version is available', () {
      // This is the real assertion. Without the policy gate these values make
      // `isUpdateAvailable` true, and both update surfaces render.
      ApplicationInfo.applicationVersion = '0.11.4';
      ApplicationInfo.latestVersionNotifier.value = '99.0.0';

      expect(ApplicationInfo.isUpdateAvailable, isFalse);
    });

    test('stays false for the exact versions the drill saw', () {
      // 0.11.4 -> 0.13.0 is what a fresh Ludwig actually offered on 2026-07-27.
      ApplicationInfo.applicationVersion = '0.11.4';
      ApplicationInfo.latestVersionNotifier.value = '0.13.0';

      expect(ApplicationInfo.isUpdateAvailable, isFalse);
    });
  });
}
