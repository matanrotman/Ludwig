import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/backup/backup_bloc.dart';
import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/backup_settings.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/restore_flow.dart';
import 'package:appflowy/workspace/presentation/settings/shared/af_dropdown_menu_entry.dart';
import 'package:appflowy/workspace/presentation/settings/shared/setting_list_tile.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_dropdown.dart';
import 'package:appflowy/workspace/presentation/settings/shared/single_setting_action.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Backup settings — Stage 3 of `specs/google-drive-backup.md`.
///
/// Lives in its own settings section (not "Cloud settings", which controls
/// which server the app talks to): toggle, destination, interval, manual
/// "back up now", and the snapshot list. Restore is wired up in Stage 4.
class SettingsBackupView extends StatelessWidget {
  const SettingsBackupView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BackupBloc>(
      create: (_) => BackupBloc()..load(),
      child: const _SettingsBackupBody(),
    );
  }
}

class _SettingsBackupBody extends StatelessWidget {
  const _SettingsBackupBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BackupBloc, BackupState>(
      builder: (context, state) {
        if (state.isLoading) {
          return SettingsBody(
            title: LocaleKeys.settings_backupPage_title.tr(),
            children: const [CircularProgressIndicator()],
          );
        }

        return SettingsBody(
          title: LocaleKeys.settings_backupPage_title.tr(),
          description: LocaleKeys.settings_backupPage_description.tr(),
          children: [
            SettingsCategory(
              title: LocaleKeys.settings_backupPage_automaticBackup_title.tr(),
              children: [
                SettingListTile(
                  label: LocaleKeys
                      .settings_backupPage_automaticBackup_toggleLabel
                      .tr(),
                  trailing: [
                    Toggle(
                      value: state.settings.enabled,
                      onChanged: (_) => context
                          .read<BackupBloc>()
                          .setEnabled(!state.settings.enabled),
                    ),
                  ],
                ),
                _DestinationRow(state: state),
                _IntervalRow(settings: state.settings),
                _LastBackupRow(status: state.status),
                SingleSettingAction(
                  label: LocaleKeys
                      .settings_backupPage_automaticBackup_backupNowDescription
                      .tr(),
                  buttonLabel: LocaleKeys
                      .settings_backupPage_automaticBackup_backupNowAction
                      .tr(),
                  onPressed: state.status.running
                      ? null
                      : () => context.read<BackupBloc>().backupNow(),
                ),
              ],
            ),
            SettingsCategory(
              title: LocaleKeys.settings_backupPage_snapshots_title.tr(),
              children: state.snapshots.isEmpty
                  ? [
                      FlowyText.regular(
                        LocaleKeys.settings_backupPage_snapshots_empty.tr(),
                      ),
                    ]
                  : state.snapshots
                      .map((snapshot) => _SnapshotRow(snapshot: snapshot))
                      .toList(),
            ),
          ],
        );
      },
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final destination = state.status.destination;
    final isManual = state.settings.destinationPath != null;
    final isDriveDetected = !isManual && state.status.destinationSource != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                destination ??
                    LocaleKeys
                        .settings_backupPage_automaticBackup_destinationNotFound
                        .tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyle.body
                    .standard(color: theme.textColorScheme.primary),
              ),
            ),
            if (isDriveDetected) ...[
              HSpace(theme.spacing.m),
              Container(
                decoration: BoxDecoration(
                  color: AFThemeExtension.of(context).tint7,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: theme.spacing.l,
                  vertical: theme.spacing.s,
                ),
                child: Text(
                  LocaleKeys.settings_backupPage_automaticBackup_driveDetected
                      .tr(),
                  style: theme.textStyle.caption
                      .standard(color: theme.textColorScheme.primary),
                ),
              ),
            ],
          ],
        ),
        VSpace(theme.spacing.m),
        Row(
          children: [
            AFOutlinedTextButton.normal(
              text: LocaleKeys
                  .settings_backupPage_automaticBackup_changeDestination
                  .tr(),
              onTap: () => context.read<BackupBloc>().pickDestination(),
            ),
            if (isManual) ...[
              HSpace(theme.spacing.m),
              AFGhostTextButton.primary(
                text: LocaleKeys
                    .settings_backupPage_automaticBackup_useAutoDetected
                    .tr(),
                onTap: () =>
                    context.read<BackupBloc>().useAutoDetectedDestination(),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// [fork:settings-width] Width of the closed interval dropdown.
const double _kIntervalDropdownWidth = 160.0;

class _IntervalRow extends StatelessWidget {
  const _IntervalRow({required this.settings});

  final BackupSettings settings;

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      label: LocaleKeys.settings_backupPage_automaticBackup_intervalLabel.tr(),
      trailing: [
        SizedBox(
          width: _kIntervalDropdownWidth,
          child: SettingsDropdown<int>(
            // [fork:settings-width] The width goes to the dropdown itself, not
            // just this SizedBox: the SizedBox alone bounds the slot but not
            // the field inside it, which then paints past the slot's right
            // edge and is clipped by the dialog. See SettingsDropdown.width.
            width: _kIntervalDropdownWidth,
            expandWidth: false,
            selectedOption: settings.intervalMinutes,
            options: BackupSettings.allowedIntervals
                .map(
                  (minutes) => buildDropdownMenuEntry<int>(
                    context,
                    value: minutes,
                    selectedValue: settings.intervalMinutes,
                    label: LocaleKeys
                        .settings_backupPage_automaticBackup_intervalOption
                        .tr(args: [minutes.toString()]),
                  ),
                )
                .toList(),
            onChanged: (minutes) =>
                context.read<BackupBloc>().setIntervalMinutes(minutes),
          ),
        ),
      ],
    );
  }
}

class _LastBackupRow extends StatelessWidget {
  const _LastBackupRow({required this.status});

  final BackupStatus status;

  @override
  Widget build(BuildContext context) {
    return FlowyText.regular(
      _statusLabel(),
      fontSize: 12,
      color: Theme.of(context).hintColor,
    );
  }

  String _statusLabel() {
    if (status.running) {
      return LocaleKeys.settings_backupPage_automaticBackup_lastBackup_running
          .tr();
    }
    if (status.lastRunAt == null) {
      return LocaleKeys.settings_backupPage_automaticBackup_lastBackup_neverRun
          .tr();
    }

    final timestamp = status.lastRunAt!.toString();
    if (status.lastOutcome == BackupOutcome.failed) {
      return LocaleKeys.settings_backupPage_automaticBackup_lastBackup_failed
          .tr(args: [timestamp]);
    }
    return LocaleKeys.settings_backupPage_automaticBackup_lastBackup_succeeded
        .tr(args: [timestamp]);
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.snapshot});

  final SnapshotInfo snapshot;

  @override
  Widget build(BuildContext context) {
    final sizeMb = (snapshot.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return SettingListTile(
      label: snapshot.timestamp.toString(),
      hint: '$sizeMb MB',
      trailing: [
        AFOutlinedTextButton.normal(
          text: LocaleKeys.settings_backupPage_snapshots_restoreAction.tr(),
          onTap: () => _startRestore(context),
        ),
      ],
    );
  }

  Future<void> _startRestore(BuildContext context) async {
    final bloc = context.read<BackupBloc>();
    final destination = bloc.state.status.destination;
    if (destination == null) {
      return;
    }
    await startRestoreFlow(
      context,
      snapshot: snapshot,
      destinationPath: destination,
    );
    // Reached on cancel or failure only (success relaunches the app) — the
    // pre-restore snapshot may already exist, so the list is stale.
    if (!bloc.isClosed) {
      await bloc.refreshSnapshots();
    }
  }
}
