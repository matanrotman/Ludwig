//! Reads a backup snapshot **without making it live**.
//!
//! `specs/restore-redesign.md`. A snapshot zip is an AppFlowy data folder, so its
//! `collab_db` can be opened read-only alongside the running workspace and its view
//! tree walked. Phase 0 proved this against a real snapshot: 97 views, 82/82 documents
//! readable, formatting intact, no Markdown anywhere in the path.
//!
//! Everything here is **read-only**. Nothing in this module writes to, renames, or even
//! resolves the live data folder — that separation is the feature's core safety property
//! and should survive any refactor.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use collab::preclude::Collab;
use collab_folder::{Folder, UserId, View};
use collab_integrate::{CollabKVAction, CollabKVDB};
use collab_plugins::local_storage::kv::KVTransactionDB;
use flowy_error::{ErrorCode, FlowyError, FlowyResult};
use flowy_sqlite::kv::KVStorePreferences;
use flowy_user_pub::session::Session;
use tracing::{info, warn};

/// One view as the restore browser needs it: enough to draw a row and decide whether it
/// can be ticked, and nothing else.
pub struct SnapshotView {
  pub id: String,
  pub parent_id: String,
  pub name: String,
  /// `collab_folder::ViewLayout` as i64, matching the app's `ViewLayoutPB`.
  pub layout: i64,
  /// A space is a Document-layout view flagged in `extra`. It has NO document collab of
  /// its own — Phase 0's probe initially read that as a load failure. Anything walking a
  /// snapshot must treat spaces as containers, not as pages.
  pub is_space: bool,
  /// This fork's folder flag (`specs/folder.md`). Also a container.
  pub is_folder: bool,
  /// Raw `View.extra`. Carries the per-page settings — direction, theme, margins — which
  /// live on the folder side rather than in the document, so they travel with the tree.
  pub extra: String,
  pub icon: String,
}

pub struct SnapshotTree {
  pub workspace_id: String,
  pub uid: i64,
  pub views: Vec<SnapshotView>,
}

/// An extracted snapshot on disk, ready to be read.
///
/// Extraction is cached per snapshot so that expanding a day in the UI doesn't unzip the
/// same archive repeatedly.
pub struct ExtractedSnapshot {
  pub data_dir: PathBuf,
}

/// Where snapshots get unpacked for reading. Deliberately the OS temp area and never
/// anywhere near the live data folder.
fn extraction_root() -> PathBuf {
  std::env::temp_dir().join("ludwig_snapshot_browse")
}

/// `collab_db_history` is the majority of a snapshot's bytes (AppFlowy writes one archive
/// per day and never prunes them) and is useless for browsing, so it is skipped. On a real
/// snapshot this is most of the archive.
fn should_extract(entry_path: &str) -> bool {
  !entry_path.contains("collab_db_history/")
}

/// Unpacks the parts of `zip_path` needed to read its folder, reusing a previous
/// extraction when one is present.
pub fn extract_for_reading(zip_path: &Path) -> FlowyResult<ExtractedSnapshot> {
  let stem = zip_path
    .file_stem()
    .and_then(|s| s.to_str())
    .ok_or_else(|| FlowyError::new(ErrorCode::InvalidParams, "snapshot path has no file name"))?;

  let dest = extraction_root().join(stem);
  let data_dir = dest.join("data");

  if data_dir.exists() {
    info!("[snapshot] reusing extraction at {:?}", data_dir);
    return Ok(ExtractedSnapshot { data_dir });
  }

  fs::create_dir_all(&dest).map_err(|e| {
    FlowyError::new(
      ErrorCode::Internal,
      format!("can't create snapshot scratch dir: {}", e),
    )
  })?;

  let file = fs::File::open(zip_path).map_err(|e| {
    FlowyError::new(
      ErrorCode::Internal,
      format!("can't open snapshot {:?}: {}", zip_path, e),
    )
  })?;
  let mut archive = zip::ZipArchive::new(file).map_err(|e| {
    FlowyError::new(
      ErrorCode::Internal,
      format!("can't read snapshot {:?}: {}", zip_path, e),
    )
  })?;

  let mut extracted = 0usize;
  let mut skipped = 0usize;
  for i in 0..archive.len() {
    let mut entry = archive
      .by_index(i)
      .map_err(|e| FlowyError::new(ErrorCode::Internal, format!("bad zip entry: {}", e)))?;

    // `enclosed_name` rejects paths that would escape the destination (zip-slip).
    let Some(relative) = entry.enclosed_name() else {
      warn!("[snapshot] skipping unsafe zip entry: {}", entry.name());
      continue;
    };
    if !should_extract(&relative.to_string_lossy()) {
      skipped += 1;
      continue;
    }

    let out_path = dest.join(&relative);
    if entry.is_dir() {
      let _ = fs::create_dir_all(&out_path);
      continue;
    }
    if let Some(parent) = out_path.parent() {
      fs::create_dir_all(parent).map_err(|e| {
        FlowyError::new(ErrorCode::Internal, format!("can't create {:?}: {}", parent, e))
      })?;
    }
    let mut out = fs::File::create(&out_path).map_err(|e| {
      FlowyError::new(
        ErrorCode::Internal,
        format!("can't write {:?}: {}", out_path, e),
      )
    })?;
    std::io::copy(&mut entry, &mut out)
      .map_err(|e| FlowyError::new(ErrorCode::Internal, format!("can't extract: {}", e)))?;
    extracted += 1;
  }

  info!(
    "[snapshot] extracted {} files ({} history entries skipped) to {:?}",
    extracted, skipped, dest
  );

  if !data_dir.exists() {
    return Err(FlowyError::new(
      ErrorCode::Internal,
      format!(
        "snapshot {:?} has no data/ folder — is it a Ludwig/AppFlowy snapshot?",
        zip_path
      ),
    ));
  }

  Ok(ExtractedSnapshot { data_dir })
}

/// Reads the view tree out of an extracted snapshot.
pub fn read_tree(data_dir: &Path) -> FlowyResult<SnapshotTree> {
  let data_dir_str = data_dir.to_str().ok_or_else(|| {
    FlowyError::new(ErrorCode::InvalidParams, "snapshot path is not valid UTF-8")
  })?;

  // The session tells us whose workspace this was; the folder collab is stored under the
  // workspace id, and every object under the uid.
  let prefs = Arc::new(KVStorePreferences::new(data_dir_str).map_err(|e| {
    FlowyError::new(
      ErrorCode::Internal,
      format!("can't open the snapshot's preferences store: {}", e),
    )
  })?);
  let session = prefs
    .get_object::<Session>("appflowy_session_cache")
    .ok_or_else(|| {
      FlowyError::new(
        ErrorCode::Internal,
        "the snapshot has no session — it may be from a different app or corrupted",
      )
    })?;

  let collab_db_path = data_dir.join(session.user_id.to_string()).join("collab_db");
  if !collab_db_path.exists() {
    return Err(FlowyError::new(
      ErrorCode::Internal,
      format!("the snapshot has no collab_db at {:?}", collab_db_path),
    ));
  }

  let db = Arc::new(CollabKVDB::open(&collab_db_path).map_err(|e| {
    FlowyError::new(
      ErrorCode::Internal,
      format!("can't open the snapshot's database: {}", e),
    )
  })?);
  let read_txn = db.read_txn();

  let workspace_id = session.workspace_id.to_string();
  let mut folder_collab = Collab::new(
    session.user_id,
    &workspace_id,
    "ludwig_snapshot_reader",
    vec![],
    false,
  );
  {
    let mut txn = folder_collab.transact_mut();
    read_txn
      .load_doc_with_txn(session.user_id, &workspace_id, &workspace_id, &mut txn)
      .map_err(|e| {
        FlowyError::new(
          ErrorCode::Internal,
          format!("can't load the snapshot's folder: {}", e),
        )
      })?;
  }

  let folder = Folder::open(UserId::from(session.user_id), folder_collab, None).map_err(|e| {
    FlowyError::new(
      ErrorCode::Internal,
      format!("can't open the snapshot's folder: {}", e),
    )
  })?;
  let folder_data = folder.get_folder_data(&workspace_id).ok_or_else(|| {
    FlowyError::new(
      ErrorCode::Internal,
      "the snapshot's folder has no data for its own workspace",
    )
  })?;

  let views = folder_data.views.iter().map(to_snapshot_view).collect();

  Ok(SnapshotTree {
    workspace_id,
    uid: session.user_id,
    views,
  })
}

fn to_snapshot_view(view: &View) -> SnapshotView {
  let extra = view.extra.clone().unwrap_or_default();
  SnapshotView {
    id: view.id.clone(),
    parent_id: view.parent_view_id.clone(),
    name: view.name.clone(),
    layout: view.layout.clone() as i64,
    is_space: view.space_info().is_some(),
    // Read from `extra` rather than a typed accessor: the folder flag is this fork's
    // own (`specs/folder.md`) and collab-folder knows nothing about it.
    is_folder: extra_flag(&extra, "is_folder"),
    extra,
    icon: view
      .icon
      .as_ref()
      .map(|icon| icon.value.clone())
      .unwrap_or_default(),
  }
}

/// True when `extra` is JSON carrying `"<key>": true`.
fn extra_flag(extra: &str, key: &str) -> bool {
  if extra.is_empty() {
    return false;
  }
  serde_json::from_str::<serde_json::Value>(extra)
    .ok()
    .and_then(|value| value.get(key).and_then(|flag| flag.as_bool()))
    .unwrap_or(false)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn skips_only_the_history_archives() {
    assert!(should_extract("data/cache.db"));
    assert!(should_extract("data/612/collab_db/000371.log"));
    assert!(!should_extract("data/612/collab_db_history/collab_db_20260719.zip"));
    // A user file that merely mentions the name must not be caught — the same
    // substring-vs-path-segment trap the backup exclusion rules were careful about.
    assert!(should_extract("data/612/collab_db/my_collab_db_history.log"));
  }

  #[test]
  fn reads_fork_flags_out_of_extra() {
    assert!(extra_flag(r#"{"is_folder":true}"#, "is_folder"));
    assert!(!extra_flag(r#"{"is_folder":false}"#, "is_folder"));
    assert!(!extra_flag(r#"{"is_space":true}"#, "is_folder"));
    assert!(!extra_flag("", "is_folder"));
    assert!(!extra_flag("not json", "is_folder"));
    // A non-bool value must not be coerced into a flag.
    assert!(!extra_flag(r#"{"is_folder":"true"}"#, "is_folder"));
  }
}
