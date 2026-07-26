import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/snapshot_browse_bloc.dart';
import 'package:appflowy/shared/backup/snapshot_browse_model.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
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
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocProvider.value(
      value: _bloc,
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
                  SizedBox(width: 220, child: _DayList(state: state)),
                  HSpace(theme.spacing.xl),
                  Expanded(child: _TreePane(state: state)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              Switch(
                value: state.showOnlyMissing,
                onChanged: (_) =>
                    context.read<SnapshotBrowseBloc>().toggleMissingOnly(),
              ),
            ],
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

    return ListView.builder(
      itemCount: state.days.length,
      itemBuilder: (context, index) {
        final day = state.days[index];
        // The two most recent days open by default: same-day mistakes are the
        // common case, and their times are what you'd reach for first (D3).
        return _DayTile(day: day, initiallyExpanded: index < 2, state: state);
      },
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
          child: Padding(
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
        rows.add(_NodeRow(node: node, depth: depth));
        flatten(node.children, depth + 1);
      }
    }

    flatten(state.tree, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Expanded(child: ListView(children: rows)),
      ],
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.node, required this.depth});

  final SnapshotNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // Containers carry the structural weight, matching the sidebar's settled
    // visual language (specs/folder.md): containers heavier, pages regular.
    final style = node.isContainer
        ? theme.textStyle.body.enhanced(color: theme.textColorScheme.primary)
        : theme.textStyle.body.standard(
            color: node.isRestorable
                ? theme.textColorScheme.primary
                // Not restorable in this phase (D4) — visible, but clearly inert.
                : theme.textColorScheme.tertiary,
          );

    return Padding(
      padding: EdgeInsets.only(left: 12.0 * depth, top: 3, bottom: 3),
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
