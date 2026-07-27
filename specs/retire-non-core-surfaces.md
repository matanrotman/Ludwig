# Retiring Grid, Board, Calendar and AI Chat from the UI

**Status: BUILT 2026-07-27 (session 16) and verified live.** The decision below is unchanged; what
follows it is now shipped. `RetiredSurfaces`
(`lib/workspace/application/retired_surfaces.dart`) is the single findable place — empty its two
sets and all four come back.

## The decision

**Grid, Board, Calendar and AI Chat stop being creatable or advertised anywhere in the UI. The code
stays in the repo, untouched, for at least a couple of months.**

The user's words: *"it's ok to remove them from the UI but keep them in the code for even a couple
of months. If we see we need them, or need blocks of them inside our pages, we can have a
discussion."*

**This is a reversible product decision, deliberately.** The one thing that would make it
irreversible — deleting the subsystem — is exactly what was *not* chosen. The reason to revisit
would be evidence (a real need, from the user's own life, per `specs/product-direction.md`), not
the passage of time.

**AI Chat is a special case worth stating separately: it is being hidden, not rejected.** The user
wants an AI chat — *"our own version, and very specific and limited."* What is being retired is
AppFlowy's general-purpose chat surface, so it does not squat on the space a deliberate one will
need. That future feature gets its own interview and spec.

## Why not delete it (the argument, with the numbers)

The first version of this argument, made in-session, was that deleting the database subsystem would
make **every future upstream merge harder, forever**. That was an assertion, and measuring it showed
it was **wrong**:

| Measurement | Result |
|---|---|
| Upstream's last commit to `lib/plugins/database` | **2025-06-16 — 13 months ago** |
| Upstream's last commit to `flowy-database2` | **2025-05-26 — 14 months ago** |
| Upstream commits to those paths in the last 6 months | **0** |
| Upstream commits to those paths over 24 months | 161 Dart + 118 Rust — busy, then stopped |
| Upstream/main commits in the last 6 months, whole repo | **2** |

You cannot conflict with a subsystem nobody is editing. **The merge-cost objection to deletion is
mostly gone**, and this is recorded so a future session does not resurrect it as though it stood.

What the subsystem actually is:

| | Total lines | Hand-written | Files |
|---|---|---|---|
| `lib/plugins/database` | 114,219 | **47,778** | 367 |
| `lib/plugins/database_document` | 1,862 | 1,862 | 5 |
| `rust-lib/flowy-database2` | 77,941 | **34,056** | 269 |
| **Total** | **~194,000** | **~82,000** | 641 |

Over half is generated (freezed/protobuf), so the honest number for "code you would be deleting or
maintaining" is **~82k lines, not 194k**.

**Coupling is smaller than it looks:** 50 files outside the plugin reference it, but **27 are
`mobile/presentation`**, which this fork does not ship. The desktop blast radius is ~23 files, and
only ~7 desktop places can create a Grid/Board/Calendar at all.

**So deletion was affordable and was still not chosen** — because it buys nothing the user wants
today and forecloses a discussion they explicitly want to keep open. Retiring the UI gets the whole
product-identity change; deleting gets a smaller binary.

**Also settled: "copy the code and make our own thing" is not a real option.** The code is already
in this repo — it *is* the copy. Vendoring changes nothing unless the original is also deleted, at
which point it is deletion with extra steps.

## Relevant finding: in-page tables already exist

`lib/plugins/document/presentation/editor_plugins/simple_table` is **11,371 lines of tables inside a
page, already shipping in this fork.** If the "we might want blocks of them inside our pages"
conversation ever happens, it starts from something built, not from nothing. What a database adds on
top is typed fields, filters, sorts, board/calendar views, and relations — and each of those should
have to justify itself individually against `specs/product-direction.md`.

## Scope

**In scope — every surface that lets you make one, or suggests one exists:**

| Surface | File |
|---|---|
| Slash menu Grid/Board/Calendar | `slash_menu/slash_menu_items/database_items.dart` |
| Inline + referenced database menu items | `database/inline_database_menu_item.dart`, `database/referenced_database_menu_item.dart` |
| CSV import (creates a Grid) | `sidebar/import/import_panel.dart` |
| AI Chat creation + actions | `view_item.dart`, `view_more_action_button.dart`, `more_view_actions.dart`, `command_palette.dart` |
| The palette's "Ask AI" entrance | `command_palette/widgets/search_ask_ai_entrance.dart` |
| Sidebar new-page type pickers | to be enumerated during the build |
| Mobile equivalents | `mobile/presentation/bottom_sheet/bottom_sheet_add_new_page.dart` and friends |

**Out of scope — deliberately:**

- **`view_ext.dart`'s layout mappings stay.** Layout → icon, plugin, tab builder must keep working,
  because an existing Grid must still open. Retiring creation is not the same as breaking what
  exists, and the user has none of these anyway — but a fork someone else builds from might.
- **No Rust change, no data migration, no deletion.** Nothing about stored data changes.
- **The AI writer block in the editor** (`editor_plugins/ai/`) is a different surface from AI Chat
  and is not covered here. If it should go too, that is a question to ask, not to assume.

## The trap this will hit, already learned once

**The surfaces are spread across many call sites, and finding them is the actual work.** This is
exactly the shape of `specs/ephemeral-pad.md`'s D12, where a "just filter it out" task turned out to
touch **seven** unfiltered surfaces including search, `@`-mentions, link-to-page and two mobile
pickers. Do this as **one deliberate sweep with a written list**, not as things are noticed — and
consider the same guard test D12 got (`pad_discovery_surfaces_test.dart` scans `lib/` and fails when
a new call site appears unclassified), because the failure mode is identical: a surface nobody
remembered still offering something that should be gone.

## How we'll know it's done

- No route through the UI — desktop or mobile, sidebar, slash menu, palette or import — produces a
  Grid, Board, Calendar or AI Chat.
- Nothing in the interface advertises that they exist.
- Existing views of those types, if any are ever encountered, still open rather than crashing.
- `flutter analyze` clean; the Rust side untouched.
- A written list of every retired surface lives in the code, so re-enabling is a known edit rather
  than archaeology.

## Multi-user readiness

This is a **product** decision, not a personal one — it applies to anyone who runs Ludwig, and it is
the change that most distinguishes Ludwig from AppFlowy for a future user. The re-enable path should
stay a single, findable place rather than 20 scattered conditions, so the decision can be revisited
as a decision.


## Session Log

### 2026-07-27 (session 16) — built, in one sweep

Built exactly as the spec asked: **one deliberate sweep with a written list**, not fixes as noticed.
No code deleted; four surfaces stop being creatable or advertised.

**`RetiredSurfaces` is the whole decision in one file.** Two sets — `layouts` and `pluginTypes` —
plus the classified surface list. Every call site routes through it rather than naming a layout
inline, so re-enabling is one edit. Two vocabularies are listed rather than converted because the app
genuinely has two: the folder speaks `ViewLayoutPB`, the plugin sandbox speaks `PluginType`, and the
mapping between them is not total (`blank`, `trash`, `databaseDocument` have no layout).

**The sidebar gate went into `pluginBuilders()`, not into each plugin's own `creatable` config.**
Upstream already has that config mechanism and it looked like the obvious hook — but those configs
live *inside* the subsystems being retired. Putting the decision in the code being retired is
precisely what turns "re-enable it" into archaeology.

**The referenced-database slash items were retired alongside the creating ones.** That is not
over-reach: with nothing creatable there is nothing to reference, so keeping them would advertise a
feature whose only possible outcome is an empty picker.

**CSV import goes too, and it is the one that stings** — a genuinely useful import, retired only
because its output is a Grid. Recorded in `import_type.dart`: if CSV ever needs to land in Ludwig it
should arrive as an in-page table, which is a feature to scope, not a filter to loosen.

**The guard test earned its keep immediately.** It scans `lib/` and fails when a new file names a
retired layout without being classified — and on its first run it caught **four** files I had missed.
All four turned out to be correctly exempt (two already-dead definition sites that nothing
references, one definition consumed by the gated builder, and a naming rule downstream of the gated
picker), but "correctly exempt" is a conclusion the test forced rather than one I reached by luck.

**Verified live:** `/grid`, `/board` and `/calendar` each return only "Link to page"; `/table` still
offers Table, so in-page tables are untouched. 469 unit tests pass, analyzer clean, Rust untouched.

**Not verified live:** the sidebar `+` menu and the mobile sheet. Synthetic clicks do not open
popovers in this app (a long-standing tooling limit, see STATUS.md), so the `+` menu rests on
`pluginBuilders()` being the single documented choke point plus the guard test. **Worth 10 seconds of
the user's own click.**
