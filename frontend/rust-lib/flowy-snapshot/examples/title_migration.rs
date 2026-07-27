//! `specs/no-titles.md` **Phase 5** — the one-off migration that moves each page's
//! name into its document as the first line.
//!
//! ```text
//!   cargo run -p flowy-snapshot --example title_migration -- <snapshot.zip>      # report only
//!   cargo run -p flowy-snapshot --example title_migration -- <data_dir> --apply  # writes
//! ```
//!
//! ## Why this is an offline tool and not an in-app migration
//!
//! It runs **once, on one workspace, ever**. After Phase 5 the title box does not
//! exist, so no page can acquire a name that isn't already its first line — there
//! is no general case to design for. Running it offline with the app quit removes
//! every hazard the spec named: no `SpaceEvent.initial` timing trap (which is what
//! silently no-oped the pre-migration snapshot), no lock contention, and no way to
//! leave a *live* workspace half-migrated behind a running editor.
//!
//! ## Two independent idempotency guards
//!
//! 1. **A marker file** next to the data folder, checked before any write.
//! 2. **The skip rule itself.** A migrated page's first line *equals its name* —
//!    which is exactly the condition for skipping. Running twice cannot double a
//!    name even with the marker deleted. Guard 1 is belt; this is braces.
//!
//! ## The one guess, and which way it errs
//!
//! Skipping a page whose first line already equals its name is a guess, named as
//! such in the spec. It errs toward **skipping**: the failure mode is a line the
//! user adds by hand, never lost writing. Nothing here deletes or overwrites — the
//! only edit it can make is inserting one paragraph at the top.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use collab::preclude::Collab;
use collab_document::blocks::{Block, DocumentData};
use collab_document::document::Document;
use collab_folder::{Folder, UserId};
use collab_integrate::{CollabKVAction, CollabKVDB};
use collab_plugins::local_storage::kv::KVTransactionDB;
use flowy_snapshot::reader::{self, SnapshotView};
use flowy_sqlite::kv::KVStorePreferences;
use flowy_user_pub::session::Session;

/// Mirrors `PadContent.nameLimit` on the Dart side. If these disagree, the skip
/// rule disagrees with the namer that wrote the names.
const NAME_LIMIT: usize = 60;
const LAYOUT_DOCUMENT: i64 = 0;
const MARKER: &str = "ludwig_no_titles_migration_v1.json";

struct Plan<'a> {
  insert: Vec<(&'a SnapshotView, String)>,
  skip_already: Vec<&'a SnapshotView>,
  skip_empty_name: Vec<&'a SnapshotView>,
  skip_container: Vec<&'a SnapshotView>,
  skip_pad: Vec<&'a SnapshotView>,
  skip_non_document: Vec<&'a SnapshotView>,
  unreadable: Vec<(&'a SnapshotView, String)>,
}

fn main() {
  let args: Vec<String> = std::env::args().collect();
  let Some(target) = args.get(1).map(PathBuf::from) else {
    eprintln!("usage: title_migration <snapshot.zip | data_dir> [--apply]");
    std::process::exit(2);
  };
  let apply = args.iter().any(|a| a == "--apply");

  // A zip is a *copy*. Writing into an extracted copy would produce a migrated
  // workspace that nothing ever reads — a silent no-op that looks like success.
  if apply && target.extension().map(|e| e == "zip").unwrap_or(false) {
    eprintln!("refusing --apply on a snapshot zip: point it at the live data folder");
    std::process::exit(2);
  }

  let data_dir = if target.extension().map(|e| e == "zip").unwrap_or(false) {
    match reader::extract_for_reading(&target) {
      Ok(e) => e.data_dir,
      Err(e) => {
        eprintln!("could not open snapshot: {e}");
        std::process::exit(1);
      },
    }
  } else {
    target.clone()
  };

  let tree = match reader::read_tree(&data_dir) {
    Ok(t) => t,
    Err(e) => {
      eprintln!("could not read the folder at {data_dir:?}: {e}");
      eprintln!("(if AppFlowy is running it holds the database lock — quit it first)");
      std::process::exit(1);
    },
  };

  let plan = build_plan(&data_dir, &tree.views);
  print_report(&target, &tree.workspace_id, tree.views.len(), &plan);

  if !apply {
    println!("\nDRY RUN — nothing was written. Re-run with --apply to migrate.");
    return;
  }

  let marker_path = data_dir.join(MARKER);
  if marker_path.exists() {
    println!("\nAlready migrated — {MARKER} is present. Nothing to do.");
    println!("{}", fs::read_to_string(&marker_path).unwrap_or_default());
    return;
  }

  println!("\n=== APPLYING ===");
  match apply_plan(&data_dir, &tree.workspace_id, tree.uid, &plan) {
    Ok(written) => {
      let marker = serde_json::json!({
        "migration": "no-titles Phase 5 — names moved into documents as first lines",
        "spec": "specs/no-titles.md",
        "workspace_id": tree.workspace_id,
        "pages_written": written,
        "pages_considered": tree.views.len(),
      });
      if let Err(e) = fs::write(&marker_path, serde_json::to_string_pretty(&marker).unwrap()) {
        eprintln!("WARNING: migrated {written} pages but could not write {MARKER}: {e}");
        eprintln!("The skip rule still makes a second run a no-op, so this is not dangerous.");
      }
      println!("\nDONE — {written} pages given a first line. Marker: {marker_path:?}");
    },
    Err(e) => {
      eprintln!("\nFAILED partway: {e}");
      eprintln!("No marker written. Re-running is safe: pages already migrated will skip.");
      std::process::exit(1);
    },
  }
}

fn build_plan<'a>(data_dir: &Path, views: &'a [SnapshotView]) -> Plan<'a> {
  let mut plan = Plan {
    insert: Vec::new(),
    skip_already: Vec::new(),
    skip_empty_name: Vec::new(),
    skip_container: Vec::new(),
    skip_pad: Vec::new(),
    skip_non_document: Vec::new(),
    unreadable: Vec::new(),
  };

  for view in views {
    if view.is_space || view.is_folder {
      plan.skip_container.push(view);
    } else if extra_flag(&view.extra, "is_pad") {
      // The pad is named by the promoter. Inserting "Pad" would write an
      // internal stored name into the user's document.
      plan.skip_pad.push(view);
    } else if view.layout != LAYOUT_DOCUMENT {
      plan.skip_non_document.push(view);
    } else if view.name.trim().is_empty() {
      plan.skip_empty_name.push(view);
    } else {
      match reader::read_document(data_dir, &view.id) {
        Ok(doc) => {
          if already_named_by_first_line(&first_line(&doc), &view.name) {
            plan.skip_already.push(view);
          } else {
            plan.insert.push((view, first_line(&doc)));
          }
        },
        Err(e) => plan.unreadable.push((view, e.to_string())),
      }
    }
  }
  plan
}

fn print_report(target: &Path, workspace_id: &str, total: usize, plan: &Plan) {
  println!("# no-titles Phase 5\n");
  println!("Source:    {}", target.display());
  println!("Workspace: {workspace_id}");
  println!("Views:     {total}\n");

  println!("## Would gain a first line: {}\n", plan.insert.len());
  for (v, first) in &plan.insert {
    println!("  + {:?}", v.name);
    println!("      first line now: {}", preview(first));
  }
  println!("\n## Skipped — first line already IS the name: {}", plan.skip_already.len());
  println!("## Skipped — no name to move:                {}", plan.skip_empty_name.len());
  println!("## Skipped — containers (spaces + folders):  {}", plan.skip_container.len());
  println!("## Skipped — the ephemeral pad:              {}", plan.skip_pad.len());
  println!("## Skipped — not a document:                 {}", plan.skip_non_document.len());
  println!("## Could not be read:                        {}", plan.unreadable.len());
  for (v, e) in &plan.unreadable {
    println!("  ! {:?} — {}", v.name, e);
  }
  println!(
    "\nWOULD WRITE: {}. WOULD SKIP: {}.",
    plan.insert.len(),
    total - plan.insert.len()
  );
}

fn apply_plan(
  data_dir: &Path,
  workspace_id: &str,
  uid: i64,
  plan: &Plan,
) -> Result<usize, String> {
  let collab_db_path = data_dir.join(uid.to_string()).join("collab_db");
  let db = Arc::new(
    CollabKVDB::open(&collab_db_path)
      .map_err(|e| format!("can't open {collab_db_path:?}: {e} (is AppFlowy still running?)"))?,
  );

  let mut written = 0usize;
  for (view, _) in &plan.insert {
    // Load, edit and flush one document at a time. A crash halfway leaves every
    // page either untouched or fully migrated — never a page with a half-written
    // block — and the skip rule makes resuming a plain re-run.
    let mut collab = Collab::new(uid, &view.id, "ludwig_title_migration", vec![], false);
    {
      let read_txn = db.read_txn();
      let mut txn = collab.transact_mut();
      read_txn
        .load_doc_with_txn(uid, workspace_id, &view.id, &mut txn)
        .map_err(|e| format!("{:?}: can't load document: {e}", view.name))?;
    }

    let mut document =
      Document::open(collab).map_err(|e| format!("{:?}: can't open document: {e}", view.name))?;
    let page_id = document
      .get_page_id()
      .ok_or_else(|| format!("{:?}: document has no page block", view.name))?;

    let text_id = uuid::Uuid::new_v4().to_string();
    let delta = serde_json::json!([{ "insert": view.name }]).to_string();
    document.apply_text_delta(&text_id, delta);

    let block = Block {
      id: uuid::Uuid::new_v4().to_string(),
      ty: "paragraph".to_string(),
      parent: page_id,
      children: uuid::Uuid::new_v4().to_string(),
      external_id: Some(text_id),
      external_type: Some("text".to_string()),
      data: HashMap::new(),
    };
    // `prev_id: None` inserts at index 0 — the top of the page.
    document
      .insert_block(block, None)
      .map_err(|e| format!("{:?}: can't insert the first line: {e}", view.name))?;

    let encoded = document
      .encode_collab()
      .map_err(|e| format!("{:?}: can't encode document: {e}", view.name))?;

    db.with_write_txn(|w_txn| {
      w_txn.flush_doc(
        uid,
        workspace_id,
        &view.id,
        encoded.state_vector.to_vec(),
        encoded.doc_state.to_vec(),
      )
    })
    .map_err(|e| format!("{:?}: can't write document back: {e}", view.name))?;

    written += 1;
    println!("  [{written}/{}] {:?}", plan.insert.len(), view.name);
  }

  Ok(written)
}

/// The document's first non-empty line, whitespace-collapsed — the Rust twin of
/// `PadContent.nameFrom`, minus truncation (kept full so the report shows what is
/// actually on the page).
fn first_line(doc: &DocumentData) -> String {
  let Some(page) = doc.blocks.get(&doc.page_id) else {
    return String::new();
  };
  let Some(children) = doc.meta.children_map.get(&page.children) else {
    return String::new();
  };
  for child_id in children {
    let Some(block) = doc.blocks.get(child_id) else {
      continue;
    };
    let collapsed = collapse_whitespace(&block_text(doc, block));
    if !collapsed.is_empty() {
      return collapsed;
    }
  }
  String::new()
}

fn block_text(doc: &DocumentData, block: &Block) -> String {
  // Text lives in the text_map keyed by external_id (current format) or inline in
  // the block's own `delta` (older documents). Both appear in a real workspace.
  if let Some(external_id) = block.external_id.as_ref() {
    if let Some(raw) = doc.meta.text_map.as_ref().and_then(|m| m.get(external_id)) {
      return delta_to_plain(raw);
    }
  }
  match block.data.get("delta") {
    Some(value) => delta_to_plain(&value.to_string()),
    None => String::new(),
  }
}

fn delta_to_plain(raw: &str) -> String {
  serde_json::from_str::<serde_json::Value>(raw)
    .ok()
    .and_then(|v| v.as_array().cloned())
    .map(|ops| {
      ops
        .iter()
        .filter_map(|op| op.get("insert").and_then(|i| i.as_str()))
        .collect::<String>()
    })
    .unwrap_or_default()
}

fn collapse_whitespace(text: &str) -> String {
  text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn already_named_by_first_line(first_line: &str, name: &str) -> bool {
  let first = first_line.trim();
  let name = name.trim();
  !first.is_empty() && (first == name || truncate_like_namer(first) == name)
}

fn truncate_like_namer(text: &str) -> String {
  let chars: Vec<char> = text.chars().collect();
  if chars.len() <= NAME_LIMIT {
    return text.to_string();
  }
  let cut: String = chars[..NAME_LIMIT].iter().collect();
  match cut.rfind(' ') {
    Some(idx) if idx > (NAME_LIMIT as f64 * 0.6) as usize => cut[..idx].to_string(),
    _ => cut.trim_end().to_string(),
  }
}

fn extra_flag(extra: &str, key: &str) -> bool {
  !extra.is_empty()
    && serde_json::from_str::<serde_json::Value>(extra)
      .ok()
      .and_then(|v| v.get(key).and_then(|f| f.as_bool()))
      .unwrap_or(false)
}

fn preview(text: &str) -> String {
  if text.is_empty() {
    return "<the page is empty>".to_string();
  }
  let chars: Vec<char> = text.chars().collect();
  if chars.len() <= 70 {
    format!("{text:?}")
  } else {
    format!("{:?}…", chars[..70].iter().collect::<String>())
  }
}

// Silences unused-import warnings for items only used behind the apply path.
#[allow(dead_code)]
fn _unused(_: &KVStorePreferences, _: &Session, _: UserId, _: Folder) {}
