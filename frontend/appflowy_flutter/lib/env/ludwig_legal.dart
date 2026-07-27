/// Where Ludwig's legal documents live, in one findable place.
///
/// Upstream links these to `appflowy.com/terms` and `appflowy.com/privacy`.
/// Inherited unchanged by a fork, that tells a Ludwig user they have agreed to
/// **another company's** terms — a legal statement about the wrong entity, and
/// one AppFlowy.IO never made about Ludwig.
///
/// The documents themselves are `LEGAL/TERMS.md` and `LEGAL/PRIVACY.md` in the
/// repository, so they are versioned with the code and the copy that applies to
/// a given release is the copy shipped alongside it.
///
/// Pointed at `main` rather than a tag on purpose: a correction to the wording
/// should reach everyone, including people running an older build, since the
/// underlying facts (no telemetry, no account, local storage) do not change
/// between versions.
class LudwigLegal {
  const LudwigLegal._();

  static const String termsUrl =
      'https://github.com/matanrotman/Ludwig/blob/main/LEGAL/TERMS.md';

  static const String privacyUrl =
      'https://github.com/matanrotman/Ludwig/blob/main/LEGAL/PRIVACY.md';
}
