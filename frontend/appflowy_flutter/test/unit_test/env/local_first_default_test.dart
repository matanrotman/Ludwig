import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/env/ludwig_server_policy.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ludwig resolves an unknown server setting to **local**, never to a cloud.
/// `specs/distribution.md` D4.
///
/// ⚠️ **What these tests can and cannot reach.** `getAuthenticatorType()` guards
/// its "nothing stored yet" branch with `!integrationMode().isUnitTest`, so that
/// branch is unreachable from here *by design* — a unit test must not write real
/// preferences. Under test, a null value falls through to the `?? "0"` default
/// and returns local for a reason unrelated to our change.
///
/// So the fresh-install path is proven by the **live drill** recorded in
/// `specs/distribution.md`'s session log, not by this file. What is proven here
/// is the branch that *is* reachable — the damaged/unrecognised value — plus the
/// mapping of every valid value, which is the part a future upstream merge is
/// most likely to break silently.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    getIt.registerFactory<KeyValueStorage>(() => DartKeyValue());
    Log.shared.disableLog = true;
  });

  Future<AuthenticatorType> resolveWithStored(String? stored) async {
    SharedPreferences.setMockInitialValues(
      stored == null ? {} : {'flutter.${KVKeys.kCloudType}': stored},
    );
    return getAuthenticatorType();
  }

  Future<String?> storedCloudType() =>
      getIt<KeyValueStorage>().get(KVKeys.kCloudType);

  group('Ludwig server policy', () {
    test('declares local-first defaults and a hidden switcher', () {
      // These are the whole of D4 and D5. If either flips, the two core-file
      // changes in cloud_env.dart and setting_cloud.dart become no-ops, so
      // assert them rather than trusting a reader to notice.
      expect(LudwigServerPolicy.defaultsToLocalServer, isTrue);
      expect(LudwigServerPolicy.showServerSwitcher, isFalse);
    });
  });

  group('getAuthenticatorType', () {
    test('resolves an unrecognised stored value to local', () async {
      // Upstream sends this case to AppFlowy Cloud. A damaged preferences file
      // must not be able to put someone on a server they never chose.
      expect(await resolveWithStored('99'), AuthenticatorType.local);
    });

    test('rewrites the unrecognised value to local, so it stays fixed',
        () async {
      // Resolving is not enough: the bad value has to be replaced, or every
      // subsequent launch re-runs the same recovery.
      await resolveWithStored('not-a-number');
      expect(await storedCloudType(), '0');
    });

    test('leaves a deliberate AppFlowy Cloud choice alone', () async {
      // The local-first default applies to installs that never chose. It must
      // not migrate anyone — this user's own install is exactly this case.
      expect(await resolveWithStored('2'), AuthenticatorType.appflowyCloud);
      expect(await storedCloudType(), '2');
    });

    test('maps every valid stored value unchanged', () async {
      expect(await resolveWithStored('0'), AuthenticatorType.local);
      expect(await resolveWithStored('2'), AuthenticatorType.appflowyCloud);
      expect(
        await resolveWithStored('3'),
        AuthenticatorType.appflowyCloudSelfHost,
      );
      expect(
        await resolveWithStored('4'),
        AuthenticatorType.appflowyCloudDevelop,
      );
    });
  });
}
