import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/restore_service.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// The in-app restore flow — Stage 4 of `specs/google-drive-backup.md`.
///
/// Two safeguards stand between the button and the swap:
///   1. a typed-confirmation dialog (the Restore button stays disabled until
///      the user types the keyword), and
///   2. [RestoreService] itself takes a pre-restore snapshot and keeps the
///      previous data folder on disk before anything replaces it.
///
/// Returns after the flow ends in cancel or failure; a successful restore
/// relaunches the app and never returns here.
Future<void> startRestoreFlow(
  BuildContext context, {
  required SnapshotInfo snapshot,
  required String destinationPath,
}) async {
  final zipPath = SnapshotRepository(BackupService.localFs)
      .snapshotsDir(destinationPath)
      .childFile(snapshot.fileName)
      .path;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _RestoreConfirmDialog(snapshot: snapshot),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RestoreProgressDialog(zipPath: zipPath),
  );
}

/// Safeguard #1: type-to-confirm. This "type the keyword to arm the button"
/// pattern exists nowhere else in the codebase, so it is built here from
/// [ConfirmPopup] plus a gated custom confirm button.
class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({required this.snapshot});

  final SnapshotInfo snapshot;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  bool _unlocked = false;

  String get _keyword => LocaleKeys.settings_backupPage_restore_keyword.tr();

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: 440,
        child: ConfirmPopup(
          title: LocaleKeys.settings_backupPage_restore_confirmTitle
              .tr(args: [widget.snapshot.timestamp.toString()]),
          description:
              LocaleKeys.settings_backupPage_restore_confirmDescription.tr(),
          // The popup's Enter-to-confirm listener would bypass the typed
          // gate; the text field's onSubmitted below re-checks the keyword
          // instead.
          enableKeyboardListener: false,
          onConfirm: (_) {},
          confirmButtonBuilder: (_) => AFFilledTextButton.destructive(
            text: LocaleKeys.settings_backupPage_restore_confirmAction.tr(),
            disabled: !_unlocked,
            onTap: _confirm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.settings_backupPage_restore_typeToConfirm
                    .tr(args: [_keyword]),
                style: theme.textStyle.caption
                    .standard(color: theme.textColorScheme.secondary),
              ),
              VSpace(theme.spacing.s),
              FlowyTextField(
                hintText: _keyword,
                showCounter: false,
                onChanged: (text) {
                  final unlocked = text.trim() == _keyword;
                  if (unlocked != _unlocked) {
                    setState(() => _unlocked = unlocked);
                  }
                },
                onSubmitted: (text) {
                  if (text.trim() == _keyword) {
                    _confirm();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    if (_unlocked) {
      Navigator.of(context).pop(true);
    }
  }
}

/// Runs [RestoreService.restore] and mirrors its phases; ends in either a
/// "Restart AppFlowy" completion state or a plain-language failure state.
class _RestoreProgressDialog extends StatefulWidget {
  const _RestoreProgressDialog({required this.zipPath});

  final String zipPath;

  @override
  State<_RestoreProgressDialog> createState() => _RestoreProgressDialogState();
}

class _RestoreProgressDialogState extends State<_RestoreProgressDialog> {
  late final RestoreService _service;
  RestoreResult? _result;

  @override
  void initState() {
    super.initState();
    _service = RestoreService.production();
    _run();
  }

  Future<void> _run() async {
    final result = await _service.restore(
      zipPath: widget.zipPath,
      confirmNewerAppVersion: _confirmNewerVersion,
    );
    // RestoreService does no logging of its own (unit-test purity) — the
    // outcome is recorded here instead.
    if (result.ok) {
      Log.info(
        '[Restore] success from ${widget.zipPath}; previous data kept at '
        '${result.preRestoreDirPath}',
      );
    } else if (result.failure != RestoreFailure.declinedNewerVersion) {
      Log.error(
        '[Restore] failed at ${result.failedPhase?.name}: '
        '${result.failure?.name} — ${result.message ?? 'no detail'}',
      );
    }
    if (!mounted) {
      return;
    }
    if (result.failure == RestoreFailure.declinedNewerVersion) {
      Navigator.of(context).pop(); // The user's own choice, not an error.
      return;
    }
    setState(() => _result = result);
  }

  Future<bool> _confirmNewerVersion(String snapshotVersion) async {
    if (!mounted) {
      return false;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: SizedBox(
          width: 440,
          child: ConfirmPopup(
            title:
                LocaleKeys.settings_backupPage_restore_newerVersionTitle.tr(),
            description: LocaleKeys
                .settings_backupPage_restore_newerVersionDescription
                .tr(
              args: [snapshotVersion, ApplicationInfo.applicationVersion],
            ),
            confirmLabel:
                LocaleKeys.settings_backupPage_restore_newerVersionAction.tr(),
            // closeOnAction would pop a second time after our own pop and
            // take the progress dialog with it.
            closeOnAction: false,
            onConfirm: (_) => Navigator.of(dialogContext).pop(true),
          ),
        ),
      ),
    );
    return proceed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final result = _result;
    // Escape/back must not dismiss a running restore (explicit pops in this
    // file still work); the barrier is already non-dismissible.
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Container(
          width: 440,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(theme.borderRadius.xl),
            color: theme.surfaceColorScheme.primary,
          ),
          padding: EdgeInsets.all(theme.spacing.xxl),
          child: result == null
              ? _buildRunning(theme)
              : result.ok
                  ? _buildSuccess(theme, result)
                  : _buildFailure(theme, result),
        ),
      ),
    );
  }

  Widget _buildRunning(AppFlowyThemeData theme) {
    return ValueListenableBuilder<RestoreProgress>(
      valueListenable: _service.progress,
      builder: (context, progress, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            theme,
            LocaleKeys.settings_backupPage_restore_inProgressTitle.tr(),
          ),
          VSpace(theme.spacing.xl),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              HSpace(theme.spacing.l),
              Expanded(
                child: Text(
                  _phaseLabel(progress.phase),
                  style: theme.textStyle.body
                      .standard(color: theme.textColorScheme.secondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(AppFlowyThemeData theme, RestoreResult result) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          LocaleKeys.settings_backupPage_restore_successTitle.tr(),
        ),
        VSpace(theme.spacing.l),
        Text(
          LocaleKeys.settings_backupPage_restore_successDescription
              .tr(args: [result.preRestoreDirPath ?? '']),
          style: theme.textStyle.body
              .standard(color: theme.textColorScheme.primary),
        ),
        VSpace(theme.spacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AFFilledTextButton.primary(
              text: LocaleKeys.settings_backupPage_restore_restartAction.tr(),
              onTap: _restart,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailure(AppFlowyThemeData theme, RestoreResult result) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          LocaleKeys.settings_backupPage_restore_failedTitle.tr(),
        ),
        VSpace(theme.spacing.l),
        Text(
          _failureLabel(result.failure),
          style: theme.textStyle.body
              .standard(color: theme.textColorScheme.primary),
        ),
        if (result.message != null) ...[
          VSpace(theme.spacing.l),
          Text(
            result.message!,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyle.caption
                .standard(color: theme.textColorScheme.secondary),
          ),
        ],
        VSpace(theme.spacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AFOutlinedTextButton.normal(
              text: LocaleKeys.button_close.tr(),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _title(AppFlowyThemeData theme, String text) {
    return Text(
      text,
      style: theme.textStyle.heading4
          .prominent(color: theme.textColorScheme.primary),
    );
  }

  void _restart() {
    // Same relaunch seam as a data-location change
    // (settings_manage_data_view.dart): leave every dialog, then rebuild the
    // whole app — startup.dart re-resolves the freshly-restored folder.
    Navigator.of(context).popUntil((route) => route.isFirst);
    runAppFlowy();
  }

  String _phaseLabel(RestorePhase phase) {
    return switch (phase) {
      RestorePhase.idle ||
      RestorePhase.confirmed =>
        LocaleKeys.settings_backupPage_restore_phase_preparing.tr(),
      RestorePhase.preRestoreSnapshot =>
        LocaleKeys.settings_backupPage_restore_phase_preRestoreSnapshot.tr(),
      RestorePhase.extracting =>
        LocaleKeys.settings_backupPage_restore_phase_extracting.tr(),
      RestorePhase.validating =>
        LocaleKeys.settings_backupPage_restore_phase_validating.tr(),
      RestorePhase.swapping =>
        LocaleKeys.settings_backupPage_restore_phase_swapping.tr(),
      RestorePhase.awaitingRelaunch ||
      RestorePhase.failed =>
        LocaleKeys.settings_backupPage_restore_phase_finishing.tr(),
    };
  }

  String _failureLabel(RestoreFailure? failure) {
    return switch (failure) {
      RestoreFailure.workspaceNotFound =>
        LocaleKeys.settings_backupPage_restore_failed_workspaceNotFound.tr(),
      RestoreFailure.preRestoreSnapshotFailed =>
        LocaleKeys.settings_backupPage_restore_failed_preRestoreSnapshot.tr(),
      RestoreFailure.extractFailed =>
        LocaleKeys.settings_backupPage_restore_failed_extract.tr(),
      RestoreFailure.manifestMissing ||
      RestoreFailure.unsupportedFormat ||
      RestoreFailure.missingCollabDb ||
      RestoreFailure.nothingExtracted =>
        LocaleKeys.settings_backupPage_restore_failed_validate.tr(),
      RestoreFailure.swapFailed =>
        LocaleKeys.settings_backupPage_restore_failed_swap.tr(),
      RestoreFailure.rollbackFailed =>
        LocaleKeys.settings_backupPage_restore_failed_rollback.tr(),
      // declinedNewerVersion never reaches the failure UI; null cannot
      // happen for a failed result but the switch must be exhaustive.
      _ => LocaleKeys.settings_backupPage_restore_failed_validate.tr(),
    };
  }
}
