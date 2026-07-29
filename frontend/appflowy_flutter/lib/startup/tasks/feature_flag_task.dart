import 'package:appflowy/shared/bidi_block_crossing.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:flutter/foundation.dart';

import '../startup.dart';

class FeatureFlagTask extends LaunchTask {
  const FeatureFlagTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    // the hotkey manager is not supported on mobile
    if (!kDebugMode) {
      return;
    }

    await FeatureFlag.initialize();

    // [fork:bidi] the editor fork owns the arrow-key commands but cannot read
    // these preferences, so the flag has to be pushed to it.
    applyVisualBlockCrossingFlag();
  }
}
