use strum_macros::Display;

use flowy_derive::{Flowy_Event, ProtoBuf_Enum};
use lib_dispatch::prelude::AFPlugin;

use crate::event_handler::read_snapshot_tree_handler;

/// Stateless plugin: every call carries the snapshot path it should read, so there is no
/// manager to own and nothing to keep in sync with the live workspace.
pub fn init() -> AFPlugin {
  AFPlugin::new()
    .name(env!("CARGO_PKG_NAME"))
    .event(SnapshotEvent::ReadSnapshotTree, read_snapshot_tree_handler)
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Display, ProtoBuf_Enum, Flowy_Event)]
#[event_err = "FlowyError"]
pub enum SnapshotEvent {
  /// Read the view tree inside a snapshot zip, without making it live.
  #[event(input = "ReadSnapshotTreePayloadPB", output = "SnapshotTreePB")]
  ReadSnapshotTree = 0,
}
