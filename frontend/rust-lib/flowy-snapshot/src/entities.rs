use flowy_derive::ProtoBuf;

/// Ask for the view tree inside one snapshot zip.
#[derive(ProtoBuf, Debug, Default, Clone)]
pub struct ReadSnapshotTreePayloadPB {
  /// Absolute path to the snapshot zip. Supplied by the Dart side, which already
  /// resolves the backup destination — no path is inferred here.
  #[pb(index = 1)]
  pub zip_path: String,
}

/// Ask for one document's content inside a snapshot, for the read-only preview (D5).
#[derive(ProtoBuf, Debug, Default, Clone)]
pub struct ReadSnapshotDocumentPayloadPB {
  /// Absolute path to the snapshot zip, as with the tree read.
  #[pb(index = 1)]
  pub zip_path: String,

  /// The view whose document to read. Must be a page — spaces and folders hold no
  /// document of their own, and asking for one is an error rather than an empty page.
  #[pb(index = 2)]
  pub view_id: String,
}

/// One view in a snapshot: enough to draw a row and decide whether it can be ticked.
#[derive(ProtoBuf, Debug, Default, Clone)]
pub struct SnapshotViewPB {
  #[pb(index = 1)]
  pub id: String,

  #[pb(index = 2)]
  pub parent_id: String,

  #[pb(index = 3)]
  pub name: String,

  /// Matches the app's `ViewLayoutPB`.
  #[pb(index = 4)]
  pub layout: i64,

  /// A space is a Document-layout view flagged in `extra`, and holds no document of its
  /// own — a container, never a page.
  #[pb(index = 5)]
  pub is_space: bool,

  /// This fork's folder flag. Also a container.
  #[pb(index = 6)]
  pub is_folder: bool,

  /// Raw `View.extra`: per-page direction, theme and margins ride here rather than in
  /// the document, so they travel with the tree.
  #[pb(index = 7)]
  pub extra: String,

  #[pb(index = 8)]
  pub icon: String,
}

#[derive(ProtoBuf, Debug, Default, Clone)]
pub struct SnapshotTreePB {
  #[pb(index = 1)]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub views: Vec<SnapshotViewPB>,
}
