//! SCRATCH PROBE — `specs/restore-redesign.md` Phase 0.
//!
//! The whole restore redesign rests on one claim, which so far comes from *reading*
//! `flowy-user/src/services/data_import/appflowy_data_import.rs`, not from running it:
//!
//!   > A backup snapshot is just an AppFlowy data folder in a zip, so we can open its
//!   > `collab_db` read-only alongside the live one, walk its view tree, and read a
//!   > document's real content out of it — no Markdown round-trip.
//!
//! If that holds, Phases 1–3 are mostly UI over an existing primitive. If it doesn't,
//! the plan changes shape. This probe answers it by doing it.
//!
//! **Reads only.** It copies a snapshot zip into a scratch directory and works there;
//! it never opens, writes to, or even resolves the live data folder.
//!
//! Point it at a snapshot with:
//!   LUDWIG_SNAPSHOT_ZIP=/path/to/AppFlowy-backup-....zip cargo test -p event-integration-test \
//!     --test main zz_phase0 -- --nocapture --ignored
//!
//! Marked `#[ignore]` because it depends on a real snapshot existing on this machine —
//! it is a probe, not a regression test. Delete once Phase 0 is signed off.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use collab::preclude::Collab;
use collab_folder::{Folder, UserId};
use collab_integrate::{CollabKVAction, CollabKVDB};
use collab_plugins::local_storage::kv::KVTransactionDB;
use flowy_sqlite::kv::KVStorePreferences;
use flowy_user_pub::session::Session;

/// Where to unpack the snapshot. Deliberately a scratch path — never anywhere near the
/// live data folder.
fn scratch_dir() -> PathBuf {
  let dir = std::env::temp_dir().join("ludwig_phase0_snapshot_probe");
  let _ = fs::remove_dir_all(&dir);
  fs::create_dir_all(&dir).unwrap();
  dir
}

fn snapshot_zip() -> Option<PathBuf> {
  if let Ok(explicit) = std::env::var("LUDWIG_SNAPSHOT_ZIP") {
    let path = PathBuf::from(explicit);
    return path.exists().then_some(path);
  }
  None
}

fn unzip(zip_path: &Path, dest: &Path) -> std::io::Result<()> {
  let status = std::process::Command::new("unzip")
    .arg("-q")
    .arg(zip_path)
    .arg("-d")
    .arg(dest)
    .status()?;
  assert!(status.success(), "unzip failed for {:?}", zip_path);
  Ok(())
}

#[tokio::test]
#[ignore]
async fn zz_phase0_read_a_snapshot_read_only() {
  let Some(zip) = snapshot_zip() else {
    println!("SKIP: set LUDWIG_SNAPSHOT_ZIP to a real snapshot zip to run this probe.");
    return;
  };

  let scratch = scratch_dir();
  println!("== Phase 0 probe ==");
  println!("snapshot: {:?}", zip.file_name().unwrap());
  println!("scratch:  {:?}", scratch);

  unzip(&zip, &scratch).expect("unzip");

  // A snapshot's payload is `data/…` — the AppFlowy data folder itself.
  let data_dir = scratch.join("data");
  assert!(
    data_dir.exists(),
    "expected a `data/` folder inside the snapshot, found: {:?}",
    fs::read_dir(&scratch)
      .unwrap()
      .filter_map(|e| e.ok().map(|e| e.file_name()))
      .collect::<Vec<_>>()
  );

  // ── Claim 1: the snapshot carries a readable session (who + which workspace) ──
  let prefs = Arc::new(
    KVStorePreferences::new(data_dir.to_str().unwrap()).expect("open snapshot cache.db"),
  );
  let session = prefs
    .get_object::<Session>("appflowy_session_cache")
    .expect("no session in the snapshot's cache.db");
  println!(
    "\n[1] session OK — uid={} workspace={}",
    session.user_id, session.workspace_id
  );

  // ── Claim 2: its collab_db opens, alongside whatever else is running ──
  let collab_db_path = data_dir
    .join(session.user_id.to_string())
    .join("collab_db");
  assert!(
    collab_db_path.exists(),
    "no collab_db at {:?}",
    collab_db_path
  );
  let db = Arc::new(CollabKVDB::open(&collab_db_path).expect("open snapshot collab_db"));
  let read_txn = db.read_txn();
  println!("[2] collab_db opened at {:?}", collab_db_path);

  // ── Claim 3: the folder loads, and we can walk the real view tree ──
  let workspace_id = session.workspace_id.to_string();
  let mut folder_collab = Collab::new(
    session.user_id,
    &workspace_id,
    "phase0_probe",
    vec![],
    false,
  );
  read_txn
    .load_doc_with_txn(
      session.user_id,
      &workspace_id,
      &workspace_id,
      &mut folder_collab.transact_mut(),
    )
    .expect("load folder collab");

  let folder = Folder::open(UserId::from(session.user_id), folder_collab, None)
    .expect("open folder from snapshot");
  let folder_data = folder
    .get_folder_data(&workspace_id)
    .expect("read folder data");

  println!(
    "[3] folder OK — {} views in the snapshot",
    folder_data.views.len()
  );

  // Print the tree the restore browser would show, so the shape is verifiable by eye.
  let by_parent: HashMap<String, Vec<_>> =
    folder_data
      .views
      .iter()
      .fold(HashMap::new(), |mut acc, view| {
        acc
          .entry(view.parent_view_id.clone())
          .or_default()
          .push(view);
        acc
      });

  fn print_tree(
    parent: &str,
    by_parent: &HashMap<String, Vec<&collab_folder::View>>,
    depth: usize,
    printed: &mut usize,
  ) {
    if depth > 4 || *printed > 40 {
      return;
    }
    if let Some(children) = by_parent.get(parent) {
      for view in children {
        println!(
          "    {}{} [{:?}]",
          "  ".repeat(depth),
          if view.name.is_empty() {
            "(untitled)"
          } else {
            &view.name
          },
          view.layout
        );
        *printed += 1;
        print_tree(&view.id, by_parent, depth + 1, printed);
      }
    }
  }
  let mut printed = 0;
  println!("\n--- view tree (first 40) ---");
  print_tree(&workspace_id, &by_parent, 0, &mut printed);

  // ── Claim 4: real document content comes out, as collab, not Markdown ──
  //
  // Note: a SPACE is also a Document-layout view (capture-and-structure decision 1),
  // but it holds no document collab — so spaces are excluded, or the probe would
  // "fail" on something that was never supposed to have content.
  let documents: Vec<_> = folder_data
    .views
    .iter()
    .filter(|v| v.layout.is_document() && v.space_info().is_none())
    .collect();

  println!("\n--- document read-back ({} documents) ---", documents.len());

  let mut loaded_ok = 0usize;
  let mut empty = 0usize;
  let mut failed: Vec<(&str, String)> = vec![];
  let mut sample: Option<(String, String)> = None;
  let mut all_texts: Vec<String> = vec![];

  for view in &documents {
    let mut doc_collab = Collab::new(session.user_id, &view.id, "phase0_probe", vec![], false);
    // The write txn must be dropped before the collab can be read back.
    let load_result = {
      let mut txn = doc_collab.transact_mut();
      read_txn.load_doc_with_txn(session.user_id, &workspace_id, &view.id, &mut txn)
    };
    match load_result {
      Ok(_) => {
        let text = doc_collab.to_json_value().to_string();
        if text.len() > 2 {
          loaded_ok += 1;
          all_texts.push(text.clone());
          // Keep the meatiest document as the sample — a stub proves less.
          if sample.as_ref().map(|(_, t)| t.len()).unwrap_or(0) < text.len() {
            sample = Some((view.name.clone(), text));
          }
        } else {
          empty += 1;
        }
      },
      Err(err) => failed.push((&view.name, err.to_string())),
    }
  }

  println!("    loaded with content: {}", loaded_ok);
  println!("    loaded but empty:    {}", empty);
  println!("    failed to load:      {}", failed.len());
  for (name, err) in failed.iter().take(5) {
    println!("      - {:?}: {}", name, err);
  }

  let (sample_name, sample_text) = sample.expect(
    "not a single document could be read out of the snapshot — the primitive does NOT hold",
  );
  println!("\n    richest page: {:?} ({} bytes)", sample_name, sample_text.len());
  println!(
    "    first 600 chars: {}",
    &sample_text.chars().take(600).collect::<String>()
  );

  // Fidelity is the whole point: the Markdown round-trip lost highlights, RTL and
  // table widths. Scanning ONE page under-tests this — a page simply may not use
  // them — so count how many pages across the whole snapshot carry each attribute.
  println!("\n    --- formatting fidelity across all {} documents ---", documents.len());
  for (marker, label) in [
    ("bg_color", "highlight"),
    ("font_color", "text colour"),
    ("text_direction", "RTL/LTR direction"),
    ("width", "table/column width"),
    ("href", "links"),
    ("bold", "bold"),
    ("font_size", "font size"),
  ] {
    let count = all_texts.iter().filter(|t| t.contains(marker)).count();
    println!("    {:<20} ({:<19}) in {} page(s)", marker, label, count);
  }

  // Per-PAGE settings (direction, page colour, margins, space/folder flags) live in
  // View.extra on the folder side, not in the document collab — so they are a separate
  // fidelity question, and they come along with the tree we already read.
  println!("\n    --- per-page settings carried in View.extra ---");
  let with_extra: Vec<_> = folder_data
    .views
    .iter()
    .filter(|v| !v.extra.clone().unwrap_or_default().is_empty())
    .collect();
  println!("    views carrying extra: {}", with_extra.len());
  for key in [
    "text_direction",
    "is_space",
    "is_folder",
    "is_temporary",
    "page_color",
    "theme_mode",
    "margin",
  ] {
    let count = with_extra
      .iter()
      .filter(|v| v.extra.clone().unwrap_or_default().contains(key))
      .count();
    println!("    {:<16} in {} view(s)", key, count);
  }

  assert!(
    loaded_ok > 0,
    "no document produced content — the primitive does NOT hold"
  );
  println!("\n[4] document content OK — the primitive HOLDS.");

  println!(
    "\n== Phase 0 verdict: a snapshot can be read read-only, in-process, \
     with real content. =="
  );

  let _ = fs::remove_dir_all(&scratch);
}
