/// Ludwig's policy on software updates, in one findable place.
///
/// **Why this exists.** Upstream AppFlowy ships an auto-updater pointed at
/// `AppFlowy-IO/AppFlowy`'s GitHub releases. Inherited unchanged by a fork, it
/// does real damage: a fresh Ludwig install showed *"New Version (0.13.0)
/// Available! Current version: 0.11.4 (Official build)"* with a working Update
/// button — i.e. Ludwig inviting its own users to replace it with AppFlowy.
/// It also phones AppFlowy's servers on launch, which contradicts the
/// local-first promise in [LudwigServerPolicy].
///
/// Found by running a real fresh-install drill, 2026-07-27; it is invisible to
/// tests because it only appears on a genuinely clean launch.
///
/// Decided the same day: **turn the whole thing off**, and keep the seam so
/// Ludwig can offer its *own* updates later without rebuilding this from
/// scratch.
class LudwigUpdatePolicy {
  const LudwigUpdatePolicy._();

  /// Whether the app checks for updates at all.
  ///
  /// False turns off the network check, the launch listener, the sidebar
  /// banner, the Settings row **and** the blocking "Update required to
  /// continue" dialog — which, left on, could lock a Ludwig user out of their
  /// own writing until they installed AppFlowy.
  static const bool checkForUpdates = false;

  /// ---------------------------------------------------------------------
  /// PLACEHOLDER — Ludwig's own update feed.
  /// ---------------------------------------------------------------------
  /// When Ludwig publishes releases (`specs/distribution.md` Phase 4), point
  /// this at Ludwig's own appcast and flip [checkForUpdates] to true. The
  /// machinery already handles the rest: [feedUrl] is consumed exactly where
  /// upstream's AppFlowy URL used to be, and `{os}`/`{arch}` are substituted
  /// by `AutoUpdateTask`.
  ///
  /// Expected shape, mirroring upstream's:
  ///   https://github.com/matanrotman/Ludwig/releases/latest/download/appcast-{os}-{arch}.xml
  ///
  /// **Do not flip [checkForUpdates] to true until this is a real Ludwig URL.**
  /// Setting it while [feedUrl] is null falls back to upstream's AppFlowy feed,
  /// which is the exact bug this policy exists to prevent — so
  /// `AutoUpdateTask` asserts against that combination rather than trusting a
  /// future reader to remember.
  ///
  /// Note that Phase 4's plan is *manual re-download, no updater in v1*, so
  /// this may stay null for a long time. That is fine; it is a seam, not a
  /// to-do.
  static const String? feedUrl = null;
}
