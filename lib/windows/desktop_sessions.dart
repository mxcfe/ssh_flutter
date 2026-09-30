// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../screens/terminal_window_screen.dart';
import '../services/session_layout.dart';
import '../services/ssh_session.dart';
import '../widgets/live_terminal.dart';
import 'win32_cursor.dart';

class _NativeWindow {
  _NativeWindow({required this.controller, required this.entry});

  final RegularWindowController controller;
  final WindowEntry entry;
}

/// 正在拖动的页签。单独通知，避免拖动时整页终端跟着重建。
class TabDragModel extends ChangeNotifier {
  String? tabId;
  String? sourceWindowId;
  String? label;
  String? hoverWindowId;
  Offset? localPosition;

  bool get active => tabId != null;

  void begin({
    required String tabId,
    required String sourceWindowId,
    required String label,
    required Offset localPosition,
  }) {
    this.tabId = tabId;
    this.sourceWindowId = sourceWindowId;
    this.label = label;
    hoverWindowId = sourceWindowId;
    this.localPosition = localPosition;
    notifyListeners();
  }

  void update({required String? hoverWindowId, required Offset localPosition}) {
    if (this.hoverWindowId == hoverWindowId && this.localPosition == localPosition) {
      return;
    }
    this.hoverWindowId = hoverWindowId;
    this.localPosition = localPosition;
    notifyListeners();
  }

  void clear() {
    tabId = null;
    sourceWindowId = null;
    label = null;
    hoverWindowId = null;
    localPosition = null;
    notifyListeners();
  }
}

/// 把 [SessionLayout] 同步成真正的系统窗口。连接对象不随窗口拆分而重建。
class DesktopSessions extends ChangeNotifier {
  final SessionLayout layout = SessionLayout();
  final Map<String, _NativeWindow> _native = {};
  final Map<String, LiveTerminal> _terminals = {};
  final TabDragModel drag = TabDragModel();
  WindowRegistry? _registry;
  bool _applyingDrag = false;
  /// 新建连接优先并入这个窗口（最近激活的终端窗）。
  String? _preferredWindowId;

  LiveTerminal terminalFor(String tabId, SshSession session) {
    return _terminals.putIfAbsent(tabId, () => LiveTerminal(session));
  }

  bool get hasRegistry => _registry != null;

  void attachRegistry(WindowRegistry registry) {
    _registry = registry;
  }

  void openWindow(SshSession session) {
    final registry = _registry;
    if (registry == null) {
      throw StateError('窗口注册表未就绪');
    }

    final targetId = _existingTargetWindowId();
    if (targetId != null) {
      final tab = layout.addTab(targetId, session);
      if (tab != null) {
        session.addListener(_onSessionChanged);
        _preferredWindowId = targetId;
        _syncTitles();
        notifyListeners();
        _activateLater(targetId);
        return;
      }
    }

    final window = layout.addWindow(session);
    session.addListener(_onSessionChanged);
    try {
      final native = _mount(window.id, windowTitle(window.id));
      _native[window.id] = native;
      registry.register(native.entry);
    } catch (e) {
      session.removeListener(_onSessionChanged);
      layout.removeWindow(window.id);
      _destroyNativeOnly(window.id);
      rethrow;
    }
    _preferredWindowId = window.id;
    notifyListeners();
    _activateLater(window.id);
  }

  String? _existingTargetWindowId() {
    final preferred = _preferredWindowId;
    if (preferred != null && layout.find(preferred) != null) {
      return preferred;
    }
    if (layout.windows.isEmpty) return null;
    return layout.windows.last.id;
  }

  void activateTab(String windowId, String tabId) {
    layout.activate(windowId, tabId);
    _preferredWindowId = windowId;
    _syncTitles();
    notifyListeners();
  }

  /// 在同一连接上按当前目录切换终端 / SFTP。
  Future<void> toggleTabMode(String tabId) async {
    final tab = layout.tabs[tabId];
    if (tab == null || !tab.session.isConnected || tab.session.modeSwitching) {
      return;
    }
    final session = tab.session;
    final path = await session.resolveWorkingDirectory();
    if (session.mode == SessionMode.sftp) {
      await session.switchToTerminal(cdPath: path);
    } else {
      await session.switchToSftp(initialPath: path);
    }
  }

  void beginTabDrag({
    required String windowId,
    required String tabId,
    required String label,
    required Offset localPosition,
  }) {
    if (drag.active || _applyingDrag) return;
    activateTab(windowId, tabId);
    drag.begin(
      tabId: tabId,
      sourceWindowId: windowId,
      label: label,
      localPosition: localPosition,
    );
  }

  void updateTabDrag(Offset localPosition) {
    if (!drag.active) return;
    drag.update(hoverWindowId: _windowIdUnderCursor(), localPosition: localPosition);
  }

  void finishTabDrag() {
    final tabId = drag.tabId;
    final source = drag.sourceWindowId;
    final hover = drag.hoverWindowId;
    if (tabId == null || source == null || _applyingDrag) {
      drag.clear();
      return;
    }
    drag.clear();
    _applyingDrag = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applyTabDrop(tabId, source, hover));
    });
  }

  Future<void> _applyTabDrop(String tabId, String source, String? hover) async {
    try {
      if (hover != null && hover != source) {
        await moveTabToWindow(tabId, hover);
      } else if (hover != source) {
        await detachTab(source, tabId);
      }
    } finally {
      _applyingDrag = false;
    }
  }

  Future<void> moveTabToWindow(String tabId, String targetWindowId) async {
    final removed = layout.moveTabTo(tabId, targetWindowId);
    if (removed != null) {
      if (_preferredWindowId == removed) _preferredWindowId = targetWindowId;
      _destroyNativeOnly(removed);
      await _afterFrame();
    }
    _preferredWindowId = targetWindowId;
    _syncTitles();
    notifyListeners();
  }

  String? _windowIdUnderCursor() {
    try {
      final cursor = Win32Cursor.cursorPosition();
      if (cursor == null) return drag.sourceWindowId;
      final engineId = WidgetsBinding.instance.platformDispatcher.engineId;
      if (engineId == null) return drag.sourceWindowId;

      final hoveredHwnd = Win32Cursor.rootWindowUnderCursor();
      final inside = <String>[];
      for (final entry in _native.entries) {
        final handle = Win32Cursor.topLevelHandle(
          engineId: engineId,
          viewId: entry.value.controller.rootView.viewId,
        );
        if (handle == null) continue;
        if (hoveredHwnd != null && handle == hoveredHwnd) return entry.key;
        final bounds = Win32Cursor.windowBounds(handle);
        if (bounds != null && Win32Cursor.contains(bounds, cursor)) {
          inside.add(entry.key);
        }
      }
      if (inside.length == 1) return inside.single;
      if (inside.contains(drag.sourceWindowId)) return drag.sourceWindowId;
      return null;
    } catch (_) {
      return drag.sourceWindowId;
    }
  }

  Future<void> detachTab(String windowId, String tabId) async {
    final registry = _registry;
    if (registry == null) return;
    final created = layout.detachTab(windowId, tabId);
    if (created == null) return;
    _syncTitles();
    notifyListeners();
    // 先让旧窗口卸下视图，再挂到新窗口，避免同一个终端被画两次。
    await _afterFrame();
    if (!identical(_registry, registry) || layout.find(created.id) == null) {
      return;
    }
    final native = _mount(created.id, windowTitle(created.id));
    _native[created.id] = native;
    registry.register(native.entry);
    notifyListeners();
    _preferredWindowId = created.id;
    _activateLater(created.id);
  }

  Future<void> mergeInto(String sourceId, String targetId) async {
    if (!layout.mergeInto(sourceId, targetId)) return;
    if (_preferredWindowId == sourceId) _preferredWindowId = targetId;
    _destroyNativeOnly(sourceId);
    await _afterFrame();
    _preferredWindowId = targetId;
    _syncTitles();
    notifyListeners();
  }

  Future<void> mergeAllInto(String targetId) async {
    final removed = layout.mergeAllInto(targetId);
    if (removed.isEmpty) return;
    for (final id in removed) {
      if (_preferredWindowId == id) _preferredWindowId = targetId;
      _destroyNativeOnly(id);
    }
    await _afterFrame();
    _preferredWindowId = targetId;
    _syncTitles();
    notifyListeners();
  }

  Future<void> closeTab(String windowId, String tabId) async {
    final result = layout.closeTab(windowId, tabId);
    if (result == null) return;
    result.tab.session.removeListener(_onSessionChanged);
    if (result.windowRemoved) {
      if (_preferredWindowId == windowId) {
        _preferredWindowId =
            layout.windows.isEmpty ? null : layout.windows.last.id;
      }
      _destroyNativeOnly(windowId);
    } else {
      _syncTitles();
    }
    notifyListeners();
    await _release(result.tab);
  }

  /// 用户点了窗口关闭按钮。
  void handleNativeClose(String windowId) {
    final native = _native.remove(windowId);
    if (native == null) return;
    final tabs = layout.removeWindow(windowId);
    for (final tab in tabs) {
      tab.session.removeListener(_onSessionChanged);
    }
    if (_preferredWindowId == windowId) {
      _preferredWindowId =
          layout.windows.isEmpty ? null : layout.windows.last.id;
    }
    _registry?.unregister(native.entry);
    notifyListeners();
    native.controller.destroy();
    for (final tab in tabs) {
      unawaited(_release(tab));
    }
  }

  Future<void> shutdownAll() async {
    final pending = <SessionTab>[];
    for (final window in List<SessionWindow>.of(layout.windows)) {
      pending.addAll(layout.removeWindow(window.id));
      _destroyNativeOnly(window.id);
    }
    for (final tab in pending) {
      tab.session.removeListener(_onSessionChanged);
    }
    _preferredWindowId = null;
    notifyListeners();
    await Future.wait(pending.map(_release));
  }

  String tabLabel(SessionTab tab) {
    final host = tab.session.currentHost?.displayTitle ?? '会话';
    final kind = tab.session.mode == SessionMode.sftp ? 'SFTP' : '终端';
    return '$kind · $host';
  }

  String windowTitle(String windowId) {
    final window = layout.find(windowId);
    if (window == null) return 'SSH';
    final tab = layout.tabs[window.activeTabId];
    if (tab == null) return 'SSH';
    final label = tabLabel(tab);
    if (window.tabIds.length <= 1) return label;
    return '$label（${window.tabIds.length}）';
  }

  void _onSessionChanged() {
    _syncTitles();
    notifyListeners();
  }

  void _syncTitles() {
    for (final window in layout.windows) {
      final native = _native[window.id];
      if (native == null) continue;
      final title = windowTitle(window.id);
      try {
        if (native.controller.title != title) {
          native.controller.setTitle(title);
        }
      } catch (_) {}
    }
  }

  _NativeWindow _mount(String windowId, String title) {
    late final WindowEntry entry;
    final controller = RegularWindowController(
      preferredSize: const Size(1100, 720),
      preferredConstraints: const BoxConstraints(
        minWidth: 720,
        minHeight: 480,
      ),
      title: title,
      delegate: _SessionWindowDelegate(
        onClose: () => handleNativeClose(windowId),
      ),
    );
    entry = WindowEntry(
      controller: controller,
      builder: (_) => SshMaterialApp(
        home: TerminalWindowScreen(windowId: windowId),
      ),
    );
    return _NativeWindow(controller: controller, entry: entry);
  }

  void _destroyNativeOnly(String windowId) {
    final native = _native.remove(windowId);
    if (native == null) return;
    _registry?.unregister(native.entry);
    native.controller.destroy();
  }

  void _activateLater(String windowId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final native = _native[windowId];
      if (native == null) return;
      try {
        native.controller.activate();
      } catch (_) {}
    });
  }

  Future<void> _release(SessionTab tab) async {
    await _afterFrame();
    _terminals.remove(tab.id)?.dispose();
    try {
      await tab.session.disconnect();
    } catch (_) {}
    tab.session.dispose();
  }

  Future<void> _afterFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
  }
}

class _SessionWindowDelegate with RegularWindowControllerDelegate {
  _SessionWindowDelegate({required this.onClose});

  final VoidCallback onClose;

  @override
  void onWindowCloseRequested(RegularWindowController controller) {
    onClose();
  }
}

/// 在主窗口子树里记下 [WindowRegistry]，供之后点击主机时开新窗口。
class RegistryBinder extends StatefulWidget {
  const RegistryBinder({super.key, required this.child});

  final Widget child;

  @override
  State<RegistryBinder> createState() => _RegistryBinderState();
}

class _RegistryBinderState extends State<RegistryBinder> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = WindowRegistry.maybeOf(context);
    if (registry != null) {
      context.read<DesktopSessions>().attachRegistry(registry);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
