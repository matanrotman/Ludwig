// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// Holds the ribbon's globally-persisted UI state: whether it is collapsed,
// which tab is showing, and whether the user has asked for the old floating
// selection toolbar back.
//
// "Globally" is deliberate — the user chose one state for the whole app rather
// than per page, so this is app-level storage (KeyValueStorage), not View.extra.

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RibbonSettingsState extends Equatable {
  const RibbonSettingsState({
    this.isCollapsed = false,
    this.activeTabId = defaultTabId,
    this.showFloatingToolbar = false,
    this.isLoaded = false,
  });

  /// The Content tab — where the user spends most of their time.
  static const String defaultTabId = 'content';

  final bool isCollapsed;
  final String activeTabId;

  /// When true the floating selection toolbar is shown as well. Off by default:
  /// the ribbon replaces it, and this toggle exists to bring it back.
  final bool showFloatingToolbar;

  /// False until persisted values have been read, so the ribbon can avoid
  /// flashing the default state on launch.
  final bool isLoaded;

  RibbonSettingsState copyWith({
    bool? isCollapsed,
    String? activeTabId,
    bool? showFloatingToolbar,
    bool? isLoaded,
  }) {
    return RibbonSettingsState(
      isCollapsed: isCollapsed ?? this.isCollapsed,
      activeTabId: activeTabId ?? this.activeTabId,
      showFloatingToolbar: showFloatingToolbar ?? this.showFloatingToolbar,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }

  @override
  List<Object?> get props =>
      [isCollapsed, activeTabId, showFloatingToolbar, isLoaded];
}

class RibbonSettingsCubit extends Cubit<RibbonSettingsState> {
  RibbonSettingsCubit({KeyValueStorage? storage})
      : _storage = storage ?? getIt<KeyValueStorage>(),
        super(const RibbonSettingsState()) {
    unawaitedLoad();
  }

  final KeyValueStorage _storage;

  /// Reads persisted state. Any missing or malformed value falls back to the
  /// default rather than throwing — a corrupt pref must not stop the editor
  /// from rendering.
  Future<void> load() async {
    final collapsed = await _storage.get(KVKeys.ribbonCollapsed);
    final activeTab = await _storage.get(KVKeys.ribbonActiveTab);
    final floating = await _storage.get(KVKeys.showFloatingToolbar);

    // The document page can be disposed while these reads are in flight.
    if (isClosed) {
      return;
    }

    emit(
      state.copyWith(
        isCollapsed: collapsed == null ? false : collapsed == 'true',
        activeTabId: (activeTab == null || activeTab.isEmpty)
            ? RibbonSettingsState.defaultTabId
            : activeTab,
        showFloatingToolbar: floating == null ? false : floating == 'true',
        isLoaded: true,
      ),
    );
  }

  void unawaitedLoad() {
    load();
  }

  Future<void> toggleCollapsed() => setCollapsed(!state.isCollapsed);

  Future<void> setCollapsed(bool value) async {
    if (state.isCollapsed == value) {
      return;
    }
    emit(state.copyWith(isCollapsed: value));
    await _storage.set(KVKeys.ribbonCollapsed, value.toString());
  }

  Future<void> setActiveTab(String tabId) async {
    if (state.activeTabId == tabId) {
      return;
    }
    emit(state.copyWith(activeTabId: tabId));
    await _storage.set(KVKeys.ribbonActiveTab, tabId);
  }

  Future<void> setShowFloatingToolbar(bool value) async {
    if (state.showFloatingToolbar == value) {
      return;
    }
    emit(state.copyWith(showFloatingToolbar: value));
    await _storage.set(KVKeys.showFloatingToolbar, value.toString());
  }
}
