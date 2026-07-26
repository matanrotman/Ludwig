import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/snapshot_browse_bloc.dart';
import 'package:appflowy/shared/backup/snapshot_browse_model.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/snapshot_document_preview.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The restore browser (`specs/restore-redesign.md` Phase 1).
///
/// **Read-only, and visibly so.** No checkboxes, no rename, no delete — Phase 1
/// answers "is what I lost even in here?", which today means unzipping an archive
/// by hand. Ticking and merging arrive in Phase 3, behind the relaunch step (D8).
class SnapshotBrowser extends StatefulWidget {
  const SnapshotBrowser({super.key, required this.destinationPath});

  final String destinationPath;

  @override
  State<SnapshotBrowser> createState() => _SnapshotBrowserState();
}

class _SnapshotBrowserState extends State<SnapshotBrowser> {
  late final SnapshotBrowseBloc _bloc = SnapshotBrowseBloc(
    destinationPath: widget.destinationPath,
    repository: SnapshotRepository(BackupService.localFs),
  )..loadDays();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _bloc.close();
    super.dispose();
  }

  /// Escape closes the browser.
  ///
  /// A keyboard hook rather than `CallbackShortcuts`, because the focus-based
  /// route never fires here: **Escape closes no dialog in this app** — not
  /// Settings either, verified live — so whatever swallows it sits above the
  /// dialog's focus scope. Fixing that app-wide is its own job; this hook is
  /// scoped to exactly as long as the browser is on screen.
  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted) {
      return false;
    }
    Navigator.of(context).maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocProvider.value(
      value: _bloc,
      child: _flatHoverTheme(
        context,
        child: BlocBuilder<SnapshotBrowseBloc, SnapshotBrowseState>(
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(state: state),
              VSpace(theme.spacing.l),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 190, child: _DayList(state: state)),
                    HSpace(theme.spacing.l),
                    // With a preview open the tree narrows to a fixed column and
                    // the page takes the rest: the preview is where the decision
                    // actually gets made, and prose needs the width far more than
                    // a list of names does. With nothing previewed the tree keeps
                    // the whole pane rather than leaving dead space beside it.
                    if (state.previewNode == null)
                      Expanded(child: _TreePane(state: state))
                    else ...[
                      SizedBox(width: 250, child: _TreePane(state: state)),
                      HSpace(theme.spacing.l),
                      Expanded(child: _PreviewPane(state: state)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Neutralises the legacy Material hover for everything in this dialog.
///
/// **The trap:** AppFlowy's `ThemeData.hoverColor` is `hoverBG2`, which in the
/// dark theme is `darkMain1` — the full-strength accent blue. Nothing else in
/// the app shows it because the app's own rows hover through `FlowyHover` with
/// explicit colours; a bare Material `InkWell`/`ExpansionTile` inherits it and
/// paints a solid blue block that swallows its own text. Any new UI built from
/// stock Material widgets needs this, or its own explicit hover colours.
Widget _flatHoverTheme(BuildContext context, {required Widget child}) {
  final theme = AppFlowyTheme.of(context);
  return Theme(
    data: Theme.of(context).copyWith(
      hoverColor: theme.fillColorScheme.contentHover,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
    child: child,
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SnapshotBrowseState state;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Browse backups',
            style: theme.textStyle.heading4.prominent(
              color: theme.textColorScheme.primary,
            ),
          ),
        ),
        if (state.selected != null && !state.comparisonUnavailable)
          Row(
            children: [
              Text(
                'Only show what’s missing',
                style: theme.textStyle.body.standard(
                  color: theme.textColorScheme.secondary,
                ),
              ),
              const HSpace(8),
              // The app's own toggle, not Material's `Switch` — the Backup page
              // three rows up uses this one, and a stock Switch reads grey in
              // both states here instead of picking up the accent.
              Toggle(
                value: state.showOnlyMissing,
                onChanged: (_) =>
                    context.read<SnapshotBrowseBloc>().toggleMissingOnly(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        const HSpace(12),
        FlowyIconButton(
          width: 24,
          icon: const FlowySvg(FlowySvgs.close_s),
          hoverColor: theme.fillColorScheme.contentHover,
          tooltipText: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.state});

  final SnapshotBrowseState state;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (state.isLoadingDays) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.days.isEmpty) {
      return Text(
        'No backups found yet.',
        style: theme.textStyle.body.standard(
          color: theme.textColorScheme.secondary,
        ),
      );
    }

    // A visible scrollbar, not the default fade-away one: a year of backups
    // lives in this list and the bottom edge otherwise reads as "that's all".
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.builder(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        itemCount: state.days.length,
        itemBuilder: (context, index) {
          final day = state.days[index];
          // The two most recent days open by default: same-day mistakes are the
          // common case, and their times are what you'd reach for first (D3).
          return _DayTile(day: day, initiallyExpanded: index < 2, state: state);
        },
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.initiallyExpanded,
    required this.state,
  });

  final SnapshotDay day;
  final bool initiallyExpanded;
  final SnapshotBrowseState state;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 12),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        _dayLabel(day.date),
        style: theme.textStyle.body.enhanced(
          color: theme.textColorScheme.primary,
        ),
      ),
      subtitle: Text(
        day.snapshots.length == 1 ? '1 backup' : '${day.snapshots.length} backups',
        style: theme.textStyle.caption.standard(
          color: theme.textColorScheme.secondary,
        ),
      ),
      children: day.snapshots.map((snapshot) {
        final isSelected = state.selected?.fileName == snapshot.fileName;
        return InkWell(
          onTap: () => context.read<SnapshotBrowseBloc>().open(snapshot),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              // The open backup carries the tinted fill; hover stays quiet.
              // The other way round (a loud hover over a text-only selection)
              // makes whatever the pointer happens to sit on look chosen.
              color: isSelected ? theme.fillColorScheme.themeSelect : null,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat.Hm().format(snapshot.timestamp.toLocal()),
                    style: theme.textStyle.body.standard(
                      color: isSelected
                          ? theme.textColorScheme.action
                          : theme.textColorScheme.primary,
                    ),
                  ),
                ),
                // A pre-restore snapshot is the "what did it look like before I
                // restored?" copy — worth calling out rather than hiding.
                if (snapshot.kind == SnapshotKind.preRestore)
                  Text(
                    'before restore',
                    style: theme.textStyle.caption.standard(
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TreePane extends StatelessWidget {
  const _TreePane({required this.state});

  final SnapshotBrowseState state;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (state.error != null) {
      return Text(
        state.error!,
        style: theme.textStyle.body.standard(color: theme.textColorScheme.error),
      );
    }
    if (state.selected == null) {
      return Text(
        'Pick a backup on the left to see what was in it.',
        style: theme.textStyle.body.standard(
          color: theme.textColorScheme.secondary,
        ),
      );
    }
    if (state.isLoadingTree) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.tree.isEmpty) {
      return Text(
        state.showOnlyMissing
            ? 'Nothing in this backup is missing from your workspace.'
            : 'This backup contains no pages.',
        style: theme.textStyle.body.standard(
          color: theme.textColorScheme.secondary,
        ),
      );
    }

    final rows = <Widget>[];
    void flatten(List<SnapshotNode> nodes, int depth) {
      for (final node in nodes) {
        rows.add(
          _NodeRow(
            node: node,
            depth: depth,
            isPreviewing: state.previewNode?.id == node.id,
          ),
        );
        flatten(node.children, depth + 1);
      }
    }

    flatten(state.tree, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Which backup am I looking at? Without this the pane is anonymous —
        // collapse its day group on the left and the answer is off-screen.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _snapshotLabel(state.selected!),
            style: theme.textStyle.caption.standard(
              color: theme.textColorScheme.secondary,
            ),
          ),
        ),
        if (state.comparisonUnavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Couldn’t compare with your current workspace, so nothing is '
              'marked as missing.',
              style: theme.textStyle.caption.standard(
                color: theme.textColorScheme.secondary,
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.depth,
    required this.isPreviewing,
  });

  final SnapshotNode node;
  final int depth;
  final bool isPreviewing;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // Containers carry the structural weight, matching the sidebar's settled
    // visual language (specs/folder.md): containers heavier, pages regular.
    final style = node.isContainer
        ? theme.textStyle.body.enhanced(color: theme.textColorScheme.primary)
        : theme.textStyle.body.standard(
            color: isPreviewing
                ? theme.textColorScheme.action
                : node.isRestorable
                    ? theme.textColorScheme.primary
                    // Not restorable in this phase (D4) — visible, but inert.
                    : theme.textColorScheme.tertiary,
          );

    final row = Container(
      decoration: BoxDecoration(
        // Same rule as the day list: the open thing carries the tinted fill,
        // hover stays quiet. Reversing it makes whatever the pointer happens to
        // rest on look chosen.
        color: isPreviewing ? theme.fillColorScheme.themeSelect : null,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              node.name.isEmpty ? 'Untitled' : node.name,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (node.isMissing) ...[
            const HSpace(8),
            _MissingBadge(),
          ],
          if (!node.isContainer && !node.isRestorable) ...[
            const HSpace(8),
            Text(
              'not yet restorable',
              style: theme.textStyle.caption.standard(
                color: theme.textColorScheme.tertiary,
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(left: 12.0 * depth, top: 1, bottom: 1),
      // Containers hold no document, so clicking one has nothing to show. It
      // stays plain text rather than a control that does nothing when pressed.
      child: node.isContainer
          ? row
          : InkWell(
              onTap: () => context.read<SnapshotBrowseBloc>().preview(node),
              borderRadius: BorderRadius.circular(6),
              child: row,
            ),
    );
  }
}

/// One page from the backup, read-only beside the tree (D5).
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.state});

  final SnapshotBrowseState state;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final node = state.previewNode;
    if (node == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                node.name.isEmpty ? 'Untitled' : node.name,
                style: theme.textStyle.heading4.prominent(
                  color: theme.textColorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Same button the header uses, with the explicit hover colour: a
            // bare Material icon button here would hover the full accent block
            // (see `_flatHoverTheme` above).
            FlowyIconButton(
              width: 24,
              icon: const FlowySvg(FlowySvgs.close_s),
              hoverColor: theme.fillColorScheme.contentHover,
              tooltipText: 'Close preview',
              onPressed: () =>
                  context.read<SnapshotBrowseBloc>().closePreview(),
            ),
          ],
        ),
        // Says plainly what you are looking at. Without it, a preview that looks
        // exactly like the live page invites the belief that it IS the live page
        // — the single most dangerous misreading on this screen.
        Text(
          'From this backup — you can read it, but not change it.',
          style: theme.textStyle.caption.standard(
            color: theme.textColorScheme.secondary,
          ),
        ),
        VSpace(theme.spacing.m),
        Expanded(child: _previewBody(context, theme, node)),
      ],
    );
  }

  Widget _previewBody(
    BuildContext context,
    AppFlowyThemeData theme,
    SnapshotNode node,
  ) {
    if (state.isLoadingPreview) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.previewError != null) {
      return Text(
        state.previewError!,
        style: theme.textStyle.body.standard(color: theme.textColorScheme.error),
      );
    }
    final data = state.preview;
    if (data == null) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: theme.backgroundColorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderColorScheme.primary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SnapshotDocumentPreview(view: node.view, data: data),
    );
  }
}

class _MissingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.fillColorScheme.themeSelect,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'not in your workspace',
        style: theme.textStyle.caption.standard(
          color: theme.textColorScheme.action,
        ),
      ),
    );
  }
}

/// "Yesterday at 22:18", and the pre-restore copies say so.
String _snapshotLabel(SnapshotInfo snapshot) {
  final local = snapshot.timestamp.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final label = 'Backup from ${_dayLabel(day)} at ${DateFormat.Hm().format(local)}';
  return snapshot.kind == SnapshotKind.preRestore
      ? '$label — taken before a restore'
      : label;
}

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) {
    return 'Today';
  }
  if (difference == 1) {
    return 'Yesterday';
  }
  // Within the last week, the weekday is how people actually remember it
  // ("it was fine on Thursday"); older than that, a date is more useful.
  if (difference < 7) {
    return DateFormat.EEEE().format(day);
  }
  return DateFormat.yMMMd().format(day);
}
