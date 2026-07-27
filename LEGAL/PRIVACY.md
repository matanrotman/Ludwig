# Ludwig — Privacy Policy

*Last updated: 27 July 2026*

**Short version: Ludwig doesn't collect anything about you. There is no account, no server of ours,
and no analytics. Your writing is a folder on your computer.**

This document exists to say that precisely, and to be honest about the few things Ludwig *does*
send over the network so you can judge them for yourself.

## Who "we" are

Ludwig is free software published by Matan Rotman. It is a fork of
[AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) and is **not affiliated with or endorsed by
AppFlowy.IO**. There is no company behind Ludwig and no service being run on your behalf.

## What Ludwig collects about you

**Nothing.**

- No account, no sign-up, no email address required to use it.
- No analytics, telemetry, usage statistics, crash reporting or error tracking. There is no
  analytics or crash-reporting library in the app at all.
- No advertising, no profiling, no third-party trackers.
- No "anonymous usage data".

Nobody — including the author — can see what you write, when you write, or that you use Ludwig.

## Where your writing lives

On your computer, in a folder you can open, copy and delete yourself:

```
~/Library/Application Support/app.ludwig.desktop/
```

It is stored **unencrypted**, like most note applications. Anyone with access to your user account —
or to an unencrypted backup of your Mac — can read it. If you keep sensitive material in Ludwig,
that is the thing to be aware of. macOS FileVault encrypts your whole disk and is the usual answer.

## What Ludwig sends over the network

Three things, all of which you control:

**1. Fonts.** Ludwig ships with two fonts built in. If you choose a different font in
Settings → Workspace, Ludwig downloads it from Google's font servers (`fonts.gstatic.com`) the first
time and caches it locally. That request tells Google your IP address and which font you asked for.
It happens only when you choose a non-bundled font, and never again for that font afterwards.

**2. Backups — only where you point them.** Ludwig can write periodic backup archives to a folder you
choose. If you choose a folder that syncs to a cloud service (Google Drive, Dropbox, iCloud), then
your writing goes wherever that service takes it, under *that* service's privacy policy, not this
one. If you choose a local folder, or turn backups off, nothing leaves your machine. Ludwig has no
backup server of its own.

**3. AppFlowy Cloud — only if you deliberately turn it on.** Ludwig is local-only by default and a
fresh install never asks you to sign in. The underlying AppFlowy sync code is still present and can
be enabled by hand. **If you do that, your writing is sent to AppFlowy.IO's servers and is governed
by [AppFlowy's privacy policy](https://appflowy.com/privacy), not this one.** We have no visibility
into and no control over that. It is off by default and we do not recommend turning it on.

Ludwig does **not** check for updates, so it does not contact any server at launch. You find out
about new versions by visiting the releases page yourself.

Links you click inside your own notes open in your normal browser and are between you and that site.

## Your rights, practically

Because there is nothing to collect, there is nothing to request, correct or delete from us. Your
data is in a folder you own:

- **Export it:** copy the folder, or use Settings → Backup.
- **Delete it:** delete the folder, or drag Ludwig and its data to the Trash.

No one needs to approve any of that, and nothing is retained anywhere else.

## Children

Ludwig is not directed at children and collects nothing from anyone, of any age.

## Changes

If this policy changes, the updated version will be published in the Ludwig repository with a new
date at the top. Since Ludwig has no way to contact you, there is no notification — the file in the
release you are running is the policy that applied when you got it.

## Contact

Questions or corrections: open an issue at
<https://github.com/matanrotman/Ludwig/issues>.
