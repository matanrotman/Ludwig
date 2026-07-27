<h1 align="center">Ludwig</h1>

<p align="center">
  <b>A scratchpad for the thought that hasn't found its place yet.</b>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/AGPL-3.0"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="License: AGPL-3.0"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20(Apple%20Silicon)-lightgrey.svg" alt="macOS, Apple Silicon">
  <img src="https://img.shields.io/badge/data-local--first-green.svg" alt="Local-first">
</p>

---

Ludwig is a note-taking app for the at-the-moment need to jot something down that hasn't yet taken a
clear place in your mind. Maybe it's notes from a meeting. A draft that might or might not become a
full document. A summary of a lesson, or an article. Thoughts for your next marketing campaign. A
short task list.

It's built so that whenever you need one, there's a scratchpad at your fingertips — and when you're
ready, you can start organizing that piece of knowledge: give it a location, structure, context. Or
not. It's up to you.

It aims to put your flow and your zone into focus. Not your productivity, efficiency or teamwork.
Just your mind, on the go.

## What that means in practice

- **It opens on a blank page.** Not a dashboard, not a template picker. Start typing; it becomes a
  page once you've written something worth keeping, named after your first line. Empty it and it
  quietly goes away again.
- **Capture never asks you where.** New notes land in a Temporary space. Filing them is a separate
  decision you can make later, or never.
- **Right-to-left actually works.** Hebrew and Arabic are first-class: per-page direction,
  bidirectional text, correct cursor behaviour, and a UI font that covers all three scripts. This is
  the part most tools get wrong.
- **Your writing stays on your machine.** No account, no server, nothing to sign into. Automatic
  backups go to a folder you choose — Google Drive, Dropbox, iCloud, anywhere.
- **It does less on purpose.** No databases, boards, calendars or AI chat. Project management is not
  a problem Ludwig is trying to solve.

## Install

**macOS on Apple Silicon (M1 and later).** Intel Macs and Windows/Linux aren't built yet.

1. Download `Ludwig.dmg` from [Releases](https://github.com/matanrotman/Ludwig/releases).
2. Open it and drag Ludwig to Applications.
3. **The first time, right-click the app and choose Open**, then confirm.

That third step is needed because Ludwig is signed with a self-signed certificate rather than a
$99/year Apple Developer one. macOS will warn you the first time and then remember. If you'd rather
not take that on trust, [build it yourself](#building-from-source) — the release notes name the
exact commit each build came from.

## Ludwig and AppFlowy

Ludwig is a fork of [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy), which is excellent, and
which Ludwig would not exist without. It diverges deliberately:

|  | AppFlowy | Ludwig |
|---|---|---|
| Default storage | AppFlowy Cloud account | Local, no account |
| Right-to-left | partial | first-class |
| Databases, boards, calendars, AI chat | yes | removed |
| Updates | automatic | download when you want to |

**Ludwig is not affiliated with or endorsed by AppFlowy.IO.** It won't sync with an AppFlowy Cloud
account, and it stores its data separately, so the two can be installed side by side.

## Building from source

Ludwig builds with the same toolchain as AppFlowy — Flutter 3.27.4 and Rust 1.85, plus `cargo-make`,
`protoc` and `protoc_plugin`. Once those are in place:

```bash
./frontend/scripts/ludwig/build_release.sh
```

The script checks the toolchain, builds the Rust core and the app, verifies the result, signs it if
you have a certificate, and prints the source commit it built from.

## License

[AGPL-3.0](LICENSE), inherited from AppFlowy. Copyright © 2026 Matan Rotman; Ludwig is a fork of
AppFlowy, © AppFlowy.IO, used under the AGPL-3.0. The corresponding source for every release is this
repository, at the commit named in that release's notes.
