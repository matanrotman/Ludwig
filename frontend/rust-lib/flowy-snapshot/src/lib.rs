//! Read-only access to backup snapshots, for the selective restore browser.
//!
//! `specs/restore-redesign.md`. Nothing in this crate writes to the live workspace —
//! Phase 1 browses, and the merge that eventually writes will live behind its own
//! deliberate step (decision D8: it runs on relaunch, never beside a live editor).

pub mod entities;
pub mod event_handler;
pub mod event_map;
pub mod protobuf;
pub mod reader;
