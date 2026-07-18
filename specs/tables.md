# Tables

## Goal
Give AppFlowy's document tables proper handling of direction and alignment, starting with the most immediate pain point — pasting a table copied from a right-to-left source — and leaving room to grow into a fuller set of table controls later.

## Current state
- AppFlowy documents support tables as a block type, but there's no direction-awareness: a pasted table always lands left-aligned with left-to-right column order, regardless of where it came from.
- Pasting a table copied from an RTL document (e.g. a Hebrew Google Doc) today loses that document's right-to-left layout — the table doesn't visually match the RTL content around it.

## Desired behavior

### Phase 1 — RTL-aware paste (this phase's scope)
- **Auto-detect on paste**: when a table is pasted and its source content is RTL (detected the same way block-level auto-direction-detection works — see `specs/rtl-support.md` Phase 2), the table is automatically right-aligned on the page, with no manual step required.
- Right-align the table itself (its position on the page) and right-align cell text. Full mirroring of column order and border/cell-corner styling is **not** part of this phase — see Out of scope.

### Later phases (not yet scoped in detail)
- **Table controllers**: a set of controls on the table (likely similar in spirit to a column/row menu) that include:
  - Manual RTL/LTR toggle for a table, independent of what was auto-detected on paste.
  - Alignment controls (table position on page, cell text alignment) usable outside of the paste flow — e.g. for tables built natively in the editor, not just pasted ones.
- These will be scoped and interviewed separately once Phase 1 is built and confirmed working.

## Out of scope (for now)
- Mirroring column order (visually reversing which column is "first") for RTL tables.
- Full border/cell-corner style mirroring.
- Manual RTL toggle / alignment controls UI (deferred to a later phase, see above).
- Drag-selecting text from a paragraph into/out of a table — flagged during scoping as a general selection-handling gap, not RTL-specific; tracked as a separate future task, not part of this spec.

## Multi-user readiness (added 2026-07-17 — see CLAUDE.md "Designing for other users")
No concern here — RTL-aware table paste is a **universal** improvement with no personal-only assumptions (it keys off the pasted content's own direction, not any setting of mine). It reuses the same direction auto-detection as `rtl-support.md`, so it inherits that feature's readiness posture. Nothing to isolate or generalize later.

## Files / interfaces involved
*(not yet explored in detail — fill in once implementation starts)*
- AppFlowy's paste-handling code path for tables (likely in the editor package or its clipboard/paste service).
- Whatever per-block direction auto-detection Phase 2 of `specs/rtl-support.md` introduces — this phase should reuse that detection logic against a table's pasted content rather than inventing a separate detector.

## To confirm with me
*(resolved via interview — kept here for the record)*
- Phase 1 scope: auto-detect on paste (not a manual toggle), right-align only (not full mirroring). ✅
- Broader "table controllers" (RTL toggle + alignment controls) confirmed as a real future direction, explicitly deferred past Phase 1. ✅

## Verification
**Phase 1:**
- Copy a table from an RTL source (e.g. a Hebrew Google Doc or Word document) and paste it into an AppFlowy document; confirm the table lands right-aligned on the page and cell text is right-aligned, with no manual step.
- Paste a table from an LTR source into the same document and confirm it's unaffected (still left-aligned, left-to-right).
- Paste an RTL table into an LTR document (and vice versa) to confirm detection is based on the pasted content's own direction, not the destination document's.

## Session Log
- **2026-07-13**: Spec created during Phase 2 RTL-support scoping interview. User asked for RTL table-paste support and requested it live in its own spec file rather than being folded into `rtl-support.md`, since they want to build out table properties further later. Phase 1 scoped to auto-detect + right-align only; broader "table controllers" (manual toggle, alignment UI) explicitly named as a future direction but not detailed yet. No code written yet — awaiting sign-off alongside `rtl-support.md` Phase 2.
