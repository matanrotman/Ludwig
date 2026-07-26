use std::path::PathBuf;

use flowy_error::FlowyError;
use lib_dispatch::prelude::{data_result_ok, AFPluginData, DataResult};

use crate::entities::{ReadSnapshotTreePayloadPB, SnapshotTreePB, SnapshotViewPB};
use crate::reader;

/// Reads one snapshot's view tree. Read-only; the live workspace is never touched.
///
/// Runs on the dispatch runtime's blocking-capable executor path like every other
/// handler — unzipping a snapshot is IO-bound and takes long enough to matter, which is
/// why extraction is cached per snapshot inside [`reader::extract_for_reading`].
pub(crate) async fn read_snapshot_tree_handler(
  payload: AFPluginData<ReadSnapshotTreePayloadPB>,
) -> DataResult<SnapshotTreePB, FlowyError> {
  let params = payload.into_inner();
  let zip_path = PathBuf::from(&params.zip_path);

  let extracted = reader::extract_for_reading(&zip_path)?;
  let tree = reader::read_tree(&extracted.data_dir)?;

  let views = tree
    .views
    .into_iter()
    .map(|view| SnapshotViewPB {
      id: view.id,
      parent_id: view.parent_id,
      name: view.name,
      layout: view.layout,
      is_space: view.is_space,
      is_folder: view.is_folder,
      extra: view.extra,
      icon: view.icon,
    })
    .collect();

  data_result_ok(SnapshotTreePB {
    workspace_id: tree.workspace_id,
    views,
  })
}
