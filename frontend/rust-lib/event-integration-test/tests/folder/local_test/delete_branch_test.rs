//! Regression tests for `specs/delete-and-trash.md` Phase 1.
//!
//! The bug these pin down (reproduced 2026-07-26, and the cause of a real page loss the day
//! before): deleting a page took its children out of sight, and permanently deleting it then
//! left them **orphaned** — still on disk, but pointing at a parent that no longer existed, so
//! they appeared in no list the app can render and had no way back through the UI.
//!
//! The invariant being defended: **no operation may leave a view whose parent does not exist.**

use event_integration_test::event_builder::EventBuilder;
use event_integration_test::EventIntegrationTest;
use flowy_folder::entities::*;
use flowy_folder::event_map::FolderEvent;

async fn restore_trash_item(test: &EventIntegrationTest, view_id: &str) {
  EventBuilder::new(test.clone())
    .event(FolderEvent::RestoreTrashItem)
    .payload(TrashIdPB {
      id: view_id.to_string(),
    })
    .async_send()
    .await;
}

async fn permanently_delete_trash_item(test: &EventIntegrationTest, view_id: &str) {
  EventBuilder::new(test.clone())
    .event(FolderEvent::PermanentlyDeleteTrashItem)
    .payload(RepeatedTrashIdPB {
      items: vec![TrashIdPB {
        id: view_id.to_string(),
      }],
    })
    .async_send()
    .await;
}

/// The core invariant. Every view the app can see must have a parent the app can see
/// (or be a top-level view whose parent is the workspace).
async fn assert_no_orphans(test: &EventIntegrationTest, context: &str) {
  let workspace = test.get_current_workspace().await;
  let all = test.get_all_views().await;
  let known_ids: Vec<String> = all
    .iter()
    .map(|v| v.id.clone())
    .chain(std::iter::once(workspace.id.clone()))
    .collect();

  let orphans: Vec<&ViewPB> = all
    .iter()
    .filter(|v| !v.parent_view_id.is_empty() && !known_ids.contains(&v.parent_view_id))
    .collect();

  assert!(
    orphans.is_empty(),
    "{context}: found {} orphaned view(s) whose parent no longer exists: {:?}",
    orphans.len(),
    orphans
      .iter()
      .map(|v| (&v.name, &v.parent_view_id))
      .collect::<Vec<_>>()
  );
}

/// Builds workspace > PARENT > CHILD > GRANDCHILD and returns the three view ids.
async fn create_branch(test: &EventIntegrationTest) -> (String, String, String) {
  let workspace = test.get_current_workspace().await;
  let parent = test.create_view(&workspace.id, "PARENT".to_string()).await;
  let child = test.create_view(&parent.id, "CHILD".to_string()).await;
  let grandchild = test.create_view(&child.id, "GRANDCHILD".to_string()).await;
  (parent.id, child.id, grandchild.id)
}

/// Deleting a page hides its whole branch, and the branch is still recoverable.
#[tokio::test]
async fn delete_view_with_children_hides_the_branch_but_keeps_it_recoverable() {
  let test = EventIntegrationTest::new_anon().await;
  let (parent_id, _child_id, _grandchild_id) = create_branch(&test).await;

  test.delete_view(&parent_id).await;

  // The trash lists the deleted ROOT only — one deleted page is one row, not three.
  let trash = test.get_trash().await;
  let trash_names: Vec<&String> = trash.items.iter().map(|t| &t.name).collect();
  assert_eq!(
    trash_names,
    vec!["PARENT"],
    "the trash should list the deleted root once, not its descendants"
  );

  // Nothing in the branch is visible while it sits in the trash.
  let all = test.get_all_views().await;
  for hidden in ["PARENT", "CHILD", "GRANDCHILD"] {
    assert!(
      !all.iter().any(|v| v.name == hidden),
      "{hidden} should not be listed while its branch is in the trash"
    );
  }

  assert_no_orphans(&test, "after deleting a page that has children").await;
}

/// Restoring the deleted root brings the ENTIRE branch back, not just the root.
#[tokio::test]
async fn restoring_a_deleted_view_restores_the_whole_branch() {
  let test = EventIntegrationTest::new_anon().await;
  let (parent_id, child_id, _grandchild_id) = create_branch(&test).await;

  test.delete_view(&parent_id).await;
  restore_trash_item(&test, &parent_id).await;

  assert!(
    test.get_trash().await.items.is_empty(),
    "the trash should be empty after restoring the only item in it"
  );

  let child_back = test
    .get_view(&parent_id)
    .await
    .child_views
    .iter()
    .any(|v| v.name == "CHILD");
  assert!(
    child_back,
    "CHILD should be back under PARENT after restore"
  );

  let grandchild_back = test
    .get_view(&child_id)
    .await
    .child_views
    .iter()
    .any(|v| v.name == "GRANDCHILD");
  assert!(
    grandchild_back,
    "GRANDCHILD should be back under CHILD after restore"
  );

  assert_no_orphans(&test, "after restoring a deleted branch").await;
}

/// THE REGRESSION. Permanently deleting a view must take its whole branch with it.
/// Before the fix this deleted only the root and left CHILD and GRANDCHILD stranded —
/// alive on disk, in no list, unreachable forever.
#[tokio::test]
async fn permanently_deleting_a_view_takes_its_whole_branch() {
  let test = EventIntegrationTest::new_anon().await;
  let (parent_id, _child_id, _grandchild_id) = create_branch(&test).await;

  test.delete_view(&parent_id).await;
  permanently_delete_trash_item(&test, &parent_id).await;

  let all = test.get_all_views().await;
  for gone in ["PARENT", "CHILD", "GRANDCHILD"] {
    assert!(
      !all.iter().any(|v| v.name == gone),
      "{gone} should be gone after its branch was permanently deleted, but it is still \
       present — this is the orphaning bug from specs/delete-and-trash.md"
    );
  }

  assert!(
    test.get_trash().await.items.is_empty(),
    "the trash should be empty after permanently deleting its only item"
  );

  assert_no_orphans(&test, "after permanently deleting a page that had children").await;
}

/// Emptying the trash must not orphan anything either.
#[tokio::test]
async fn emptying_the_trash_takes_whole_branches() {
  let test = EventIntegrationTest::new_anon().await;
  let (parent_id, _child_id, _grandchild_id) = create_branch(&test).await;

  test.delete_view(&parent_id).await;
  EventBuilder::new(test.clone())
    .event(FolderEvent::PermanentlyDeleteAllTrashItem)
    .async_send()
    .await;

  let all = test.get_all_views().await;
  for gone in ["PARENT", "CHILD", "GRANDCHILD"] {
    assert!(
      !all.iter().any(|v| v.name == gone),
      "{gone} should be gone after the trash was emptied"
    );
  }

  assert_no_orphans(&test, "after emptying the trash").await;
}

/// A child that was deleted on its own, and then swallowed by its parent's deletion,
/// must not leave a stale entry behind in the trash section.
#[tokio::test]
async fn separately_trashed_child_does_not_linger_after_the_parent_is_deleted() {
  let test = EventIntegrationTest::new_anon().await;
  let (parent_id, child_id, _grandchild_id) = create_branch(&test).await;

  // Delete the child first, then the parent — both are in the trash section now.
  test.delete_view(&child_id).await;
  test.delete_view(&parent_id).await;

  permanently_delete_trash_item(&test, &parent_id).await;

  assert!(
    test.get_trash().await.items.is_empty(),
    "the separately-trashed child should not linger in the trash after its parent's \
     branch was permanently deleted"
  );

  assert_no_orphans(
    &test,
    "after permanently deleting a parent whose child was trashed separately",
  )
  .await;
}
