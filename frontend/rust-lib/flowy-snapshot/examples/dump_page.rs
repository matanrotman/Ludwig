//! Read-only diagnostic: dump a page's blocks in document order.
//!
//! Written 2026-07-27 (session 17) to investigate a reported corruption after the
//! no-titles Phase 5 migration. It only ever reads — there is no write path here at
//! all — so it is safe to point at a live data folder or at a snapshot zip.
//!
//! ```text
//!   cargo run -p flowy-snapshot --example dump_page -- <snapshot.zip|data_dir> <name substring>
//! ```

use std::path::PathBuf;

use collab_document::blocks::{Block, DocumentData};
use flowy_snapshot::reader;

fn main() {
  let args: Vec<String> = std::env::args().collect();
  let Some(target) = args.get(1).map(PathBuf::from) else {
    eprintln!("usage: dump_page <snapshot.zip | data_dir> [name substring]");
    eprintln!("       with no substring it dumps every page — diff two of those to see what moved");
    std::process::exit(2);
  };
  // No needle = dump everything, so two runs can be diffed against each other.
  let needle = args.get(2).cloned().unwrap_or_default();

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
      std::process::exit(1);
    },
  };

  let mut matches: Vec<_> = tree
    .views
    .iter()
    .filter(|v| v.name.contains(needle.as_str()))
    .collect();
  // Sort by id so two dumps are diffable — folder order is not stable between reads.
  matches.sort_by(|a, b| a.id.cmp(&b.id));

  if matches.is_empty() {
    eprintln!("no view whose name contains {needle:?}");
    std::process::exit(1);
  }

  for view in matches {
    println!("=== {:?}", view.name);
    println!("    id:     {}", view.id);
    println!("    layout: {}  space: {}  folder: {}", view.layout, view.is_space, view.is_folder);
    println!("    extra:  {}", view.extra);

    match reader::read_document(&data_dir, &view.id) {
      Ok(doc) => dump(&doc),
      Err(e) => println!("    !! could not read document: {e}"),
    }
    println!();
  }
}

fn dump(doc: &DocumentData) {
  let Some(page) = doc.blocks.get(&doc.page_id) else {
    println!("    !! no page block ({})", doc.page_id);
    return;
  };
  let Some(children) = doc.meta.children_map.get(&page.children) else {
    println!("    !! page has no children array ({})", page.children);
    return;
  };

  println!("    blocks: {} top-level, {} total", children.len(), doc.blocks.len());
  for (i, child_id) in children.iter().enumerate() {
    let Some(block) = doc.blocks.get(child_id) else {
      println!("    [{i:>3}] !! DANGLING child id {child_id} — referenced but no block");
      continue;
    };
    let text = block_text(doc, block);
    // Block id + external_id are what distinguish "a block was inserted/deleted" from
    // "an existing block's text was overwritten" — the whole question in a corruption.
    println!(
      "    [{i:>3}] {:<14} blk={} ext={} {}",
      block.ty,
      &block.id,
      block.external_id.as_deref().unwrap_or("-"),
      preview(&text)
    );
    // A nested list/toggle keeps its content in its own children array.
    if let Some(sub) = doc.meta.children_map.get(&block.children) {
      for (j, gid) in sub.iter().enumerate() {
        match doc.blocks.get(gid) {
          Some(gb) => println!(
            "          {i}.{j} {:<12} {}",
            gb.ty,
            preview(&block_text(doc, gb))
          ),
          None => println!("          {i}.{j} !! DANGLING {gid}"),
        }
      }
    }
  }
}

fn block_text(doc: &DocumentData, block: &Block) -> String {
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

fn preview(text: &str) -> String {
  if text.is_empty() {
    return "<empty>".to_string();
  }
  // LUDWIG_DUMP_FULL=1 prints untruncated text — needed when the dump is being used
  // to recover content, rather than to compare two dumps.
  if std::env::var("LUDWIG_DUMP_FULL").is_ok() {
    return text.to_string();
  }
  let chars: Vec<char> = text.chars().collect();
  if chars.len() <= 90 {
    format!("{text:?}")
  } else {
    format!("{:?}…", chars[..90].iter().collect::<String>())
  }
}
