//! `specs/restore-redesign.md` Phase 1 — reading a snapshot's view tree through the
//! real event dispatcher, the same path the restore browser uses.
//!
//! The failure-path tests run everywhere. The happy path needs an actual snapshot on
//! this machine, so it is `#[ignore]`d and takes its path from `LUDWIG_SNAPSHOT_ZIP`:
//!
//!   LUDWIG_SNAPSHOT_ZIP=/path/to/AppFlowy-backup-….zip \
//!     cargo test -p event-integration-test --test main snapshot_browse -- --ignored --nocapture
//!
//! It reads a **copy** of a snapshot and never touches the live data folder.

use std::path::PathBuf;

use event_integration_test::event_builder::EventBuilder;
use event_integration_test::EventIntegrationTest;
use flowy_snapshot::entities::{ReadSnapshotTreePayloadPB, SnapshotTreePB};
use flowy_snapshot::event_map::SnapshotEvent;

async fn read_tree(
  test: &EventIntegrationTest,
  zip_path: &str,
) -> Result<SnapshotTreePB, flowy_error::FlowyError> {
  EventBuilder::new(test.clone())
    .event(SnapshotEvent::ReadSnapshotTree)
    .payload(ReadSnapshotTreePayloadPB {
      zip_path: zip_path.to_string(),
    })
    .async_send()
    .await
    .parse::<SnapshotTreePB>()
}

/// A path that isn't there must come back as a clean error, not a panic and not an
/// empty tree — an empty tree would read as "your backup contains nothing", which is
/// the most alarming possible lie for this feature to tell.
#[tokio::test]
async fn missing_snapshot_reports_an_error_rather_than_an_empty_tree() {
  let test = EventIntegrationTest::new_anon().await;
  let result = read_tree(&test, "/definitely/not/here/nope.zip").await;
  assert!(
    result.is_err(),
    "a missing snapshot must be an error, not an empty tree"
  );
}

/// Likewise for a file that exists but isn't a snapshot.
#[tokio::test]
async fn non_snapshot_file_reports_an_error() {
  let test = EventIntegrationTest::new_anon().await;

  let junk = std::env::temp_dir().join("ludwig_not_a_snapshot.zip");
  std::fs::write(&junk, b"this is not a zip").unwrap();

  let result = read_tree(&test, junk.to_str().unwrap()).await;
  assert!(
    result.is_err(),
    "a non-snapshot file must be an error, not an empty tree"
  );

  let _ = std::fs::remove_file(&junk);
}

/// The happy path, against a real snapshot.
#[tokio::test]
#[ignore]
async fn reads_a_real_snapshot_tree() {
  let Ok(zip) = std::env::var("LUDWIG_SNAPSHOT_ZIP") else {
    println!("SKIP: set LUDWIG_SNAPSHOT_ZIP to run this.");
    return;
  };
  if !PathBuf::from(&zip).exists() {
    println!("SKIP: {} does not exist.", zip);
    return;
  }

  let test = EventIntegrationTest::new_anon().await;
  let tree = read_tree(&test, &zip).await.expect("read snapshot tree");

  println!(
    "snapshot workspace {} — {} views",
    tree.workspace_id,
    tree.views.len()
  );

  assert!(!tree.workspace_id.is_empty(), "workspace id missing");
  assert!(
    !tree.views.is_empty(),
    "a real snapshot should contain views"
  );

  // Every row the browser draws needs an id and a parent, or the tree can't be built.
  for view in &tree.views {
    assert!(!view.id.is_empty(), "a view came back with no id");
    assert!(
      !view.parent_id.is_empty(),
      "view {:?} came back with no parent",
      view.name
    );
  }

  // Containers must be identifiable, or Phase 1 can't grey out what isn't tickable
  // and Phase 3 can't resolve "back where it came from".
  let spaces = tree.views.iter().filter(|v| v.is_space).count();
  let folders = tree.views.iter().filter(|v| v.is_folder).count();
  println!("  {} space(s), {} folder(s)", spaces, folders);
  assert!(
    spaces > 0,
    "no spaces found — a real workspace always has at least Temporary"
  );

  // Per-page settings ride on the folder side, not in the document, so they must
  // survive the trip as `extra`.
  let with_extra = tree.views.iter().filter(|v| !v.extra.is_empty()).count();
  println!("  {} view(s) carrying per-page settings", with_extra);

  // Reading the same snapshot twice must be cheap and identical — the browser
  // re-reads whenever a day is expanded, and extraction is cached for that reason.
  let again = read_tree(&test, &zip).await.expect("re-read snapshot tree");
  assert_eq!(
    tree.views.len(),
    again.views.len(),
    "re-reading the same snapshot produced a different tree"
  );
}
