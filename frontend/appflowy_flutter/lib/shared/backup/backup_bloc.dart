import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/backup_settings.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// UI-facing state for the Backup settings page.
class BackupState {
  const BackupState({
    this.settings = const BackupSettings(),
    this.status = const BackupStatus(),
    this.snapshots = const [],
    this.isLoading = true,
  });

  final BackupSettings settings;
  final BackupStatus status;
  final List<SnapshotInfo> snapshots;
  final bool isLoading;

  BackupState copyWith({
    BackupSettings? settings,
    BackupStatus? status,
    List<SnapshotInfo>? snapshots,
    bool? isLoading,
  }) =>
      BackupState(
        settings: settings ?? this.settings,
        status: status ?? this.status,
        snapshots: snapshots ?? this.snapshots,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Drives the Backup settings page.
///
/// Mirrors the running [BackupService]'s live [BackupService.status] and
/// persists settings edits through [BackupSettingsStore], then tells the
/// service to re-arm its timer ([BackupService.settingsChanged]) so a change
/// takes effect without an app restart.
class BackupBloc extends Cubit<BackupState> {
  BackupBloc({BackupService? service, FilePickerService? filePicker})
      : _service = service ?? getIt<BackupService>(),
        _filePicker = filePicker ?? getIt<FilePickerService>(),
        _store = BackupSettingsStore(getIt<KeyValueStorage>()),
        super(const BackupState()) {
    _service.status.addListener(_onServiceStatusChanged);
  }

  final BackupService _service;
  final FilePickerService _filePicker;
  final BackupSettingsStore _store;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final settings = await _store.loadSettings();
    final status = _service.status.value;
    final snapshots = await _snapshotsFor(status.destination);
    emit(
      state.copyWith(
        settings: settings,
        status: status,
        snapshots: snapshots,
        isLoading: false,
      ),
    );
  }

  Future<void> setEnabled(bool enabled) =>
      _updateSettings(state.settings.copyWith(enabled: enabled));

  Future<void> setIntervalMinutes(int minutes) =>
      _updateSettings(state.settings.copyWith(intervalMinutes: minutes));

  /// Opens a directory picker and, if the user chose one, switches the
  /// destination to it. A cancelled picker is a no-op.
  Future<void> pickDestination() async {
    final path = await _filePicker.getDirectoryPath();
    if (path == null) {
      return;
    }
    await _updateSettings(state.settings.copyWith(destinationPath: path));
  }

  /// Reverts a manual destination pick back to Drive auto-detection.
  Future<void> useAutoDetectedDestination() =>
      _updateSettings(state.settings.copyWith(clearDestination: true));

  Future<void> backupNow() async {
    await _service.backupNow(trigger: BackupTrigger.manual);
    await refreshSnapshots();
  }

  Future<void> refreshSnapshots() async {
    final snapshots = await _snapshotsFor(_service.status.value.destination);
    emit(state.copyWith(snapshots: snapshots));
  }

  Future<void> _updateSettings(BackupSettings settings) async {
    await _store.saveSettings(settings);
    emit(state.copyWith(settings: settings));
    await _service.settingsChanged();
    await refreshSnapshots();
  }

  Future<List<SnapshotInfo>> _snapshotsFor(String? destination) {
    if (destination == null) {
      return Future.value(const []);
    }
    return SnapshotRepository(BackupService.localFs).list(destination);
  }

  void _onServiceStatusChanged() {
    emit(state.copyWith(status: _service.status.value));
  }

  @override
  Future<void> close() {
    _service.status.removeListener(_onServiceStatusChanged);
    return super.close();
  }
}
