/// Ludwig's policy on servers, in one findable place.
///
/// Ludwig is a local-first app: your writing lives on the machine you wrote it
/// on, and a fresh install never opts anyone into a server they did not choose.
/// Upstream AppFlowy takes the opposite default — it points a fresh install at
/// AppFlowy Cloud — so these constants are a genuine fork behaviour change, not
/// a configuration of an existing one.
///
/// This file exists so that the two core files which consult it
/// ([cloud_env.dart] and [setting_cloud.dart]) each carry a one-line change,
/// keeping future merges with upstream cheap, and so that "what does Ludwig do
/// differently about servers?" has a single answer rather than several.
///
/// Decided 2026-07-27, `specs/distribution.md` D4 + D5.
class LudwigServerPolicy {
  const LudwigServerPolicy._();

  /// What a fresh install resolves to when no server has ever been chosen, and
  /// what an unrecognised stored value falls back to.
  ///
  /// Both matter. The second is the quieter of the two: a corrupt preferences
  /// file should not be able to put a downloaded build onto someone else's
  /// server without them ever asking for it.
  static const bool defaultsToLocalServer = true;

  /// Whether Settings shows the control that switches between local storage and
  /// the various AppFlowy Cloud servers.
  ///
  /// False for **every** Ludwig build, the user's own included (their explicit
  /// choice, 2026-07-27, over the narrower "hide it only in release builds").
  /// The reasoning: a switch that is present for the person testing and absent
  /// for everyone else means the shipped path is the one nobody exercises.
  ///
  /// **Consequence worth knowing before flipping this back:** with the switcher
  /// hidden there is no in-app route between local and cloud. Changing servers
  /// becomes a preferences edit — see `STATUS.md`, "Switching Ludwig between
  /// local and AppFlowy Cloud", which records the exact command. This does not
  /// migrate anyone: an install already on AppFlowy Cloud stays there, because
  /// the stored value is untouched and only the *control* disappears.
  static const bool showServerSwitcher = false;
}
