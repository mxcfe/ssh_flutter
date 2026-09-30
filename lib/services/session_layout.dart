import 'package:uuid/uuid.dart';

import 'ssh_session.dart';

/// 一个终端或 SFTP 页签，独占一条 SSH 连接。
class SessionTab {
  SessionTab({required this.id, required this.session});

  final String id;
  final SshSession session;
}

/// 一个系统窗口里的页签集合。
class SessionWindow {
  SessionWindow({
    required this.id,
    required List<String> tabIds,
    required this.activeTabId,
  }) : tabIds = List<String>.of(tabIds);

  final String id;
  final List<String> tabIds;
  String activeTabId;
}

/// 页签在窗口之间的归属。不创建原生窗口，方便单独测试合并与拆分。
class SessionLayout {
  SessionLayout({String Function()? newId}) : _newId = newId ?? (() => _uuid.v4());

  static const Uuid _uuid = Uuid();
  final String Function() _newId;

  final List<SessionWindow> windows = [];
  final Map<String, SessionTab> tabs = {};

  SessionWindow? find(String id) {
    for (final window in windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  SessionWindow addWindow(SshSession session) {
    final tab = SessionTab(id: _newId(), session: session);
    final window = SessionWindow(
      id: _newId(),
      tabIds: [tab.id],
      activeTabId: tab.id,
    );
    tabs[tab.id] = tab;
    windows.add(window);
    return window;
  }

  /// 在已有窗口追加页签并激活。窗口不存在时返回 null。
  SessionTab? addTab(String windowId, SshSession session) {
    final window = find(windowId);
    if (window == null) return null;
    final tab = SessionTab(id: _newId(), session: session);
    tabs[tab.id] = tab;
    window.tabIds.add(tab.id);
    window.activeTabId = tab.id;
    return tab;
  }

  void activate(String windowId, String tabId) {
    final window = find(windowId);
    if (window == null || !window.tabIds.contains(tabId)) return;
    window.activeTabId = tabId;
  }

  /// 把一个页签移到 [targetWindowId]。来源窗口被搬空时移除并返回它的 id。
  String? moveTabTo(String tabId, String targetWindowId) {
    SessionWindow? source;
    for (final window in windows) {
      if (window.tabIds.contains(tabId)) {
        source = window;
        break;
      }
    }
    final target = find(targetWindowId);
    if (source == null || target == null || source.id == target.id) {
      return null;
    }
    source.tabIds.remove(tabId);
    if (!target.tabIds.contains(tabId)) {
      target.tabIds.add(tabId);
    }
    target.activeTabId = tabId;
    if (source.tabIds.isEmpty) {
      windows.remove(source);
      return source.id;
    }
    if (source.activeTabId == tabId) {
      source.activeTabId = source.tabIds.first;
    }
    return null;
  }

  /// 把页签拆成新窗口。窗口里只剩这一个页签时返回 null。
  SessionWindow? detachTab(String windowId, String tabId) {
    final window = find(windowId);
    if (window == null || window.tabIds.length < 2) return null;
    if (!window.tabIds.remove(tabId)) return null;
    if (window.activeTabId == tabId) {
      window.activeTabId = window.tabIds.first;
    }
    final created = SessionWindow(
      id: _newId(),
      tabIds: [tabId],
      activeTabId: tabId,
    );
    windows.add(created);
    return created;
  }

  /// 把 [sourceId] 的全部页签并入 [targetId]，并移除来源窗口。
  bool mergeInto(String sourceId, String targetId) {
    if (sourceId == targetId) return false;
    final source = find(sourceId);
    final target = find(targetId);
    if (source == null || target == null) return false;
    for (final id in source.tabIds) {
      if (!target.tabIds.contains(id)) {
        target.tabIds.add(id);
      }
    }
    windows.remove(source);
    return true;
  }

  /// 把其余窗口全部并入 [targetId]。返回被移除的窗口 id。
  List<String> mergeAllInto(String targetId) {
    final others = windows
        .map((window) => window.id)
        .where((id) => id != targetId)
        .toList(growable: false);
    final removed = <String>[];
    for (final id in others) {
      if (mergeInto(id, targetId)) removed.add(id);
    }
    return removed;
  }

  /// 关闭页签。窗口因此变空时会一并移除。
  ({SessionTab tab, bool windowRemoved})? closeTab(
    String windowId,
    String tabId,
  ) {
    final window = find(windowId);
    final tab = tabs.remove(tabId);
    if (window == null || tab == null) {
      if (tab != null) tabs[tabId] = tab;
      return null;
    }
    window.tabIds.remove(tabId);
    if (window.tabIds.isEmpty) {
      windows.remove(window);
      return (tab: tab, windowRemoved: true);
    }
    if (window.activeTabId == tabId) {
      window.activeTabId = window.tabIds.first;
    }
    return (tab: tab, windowRemoved: false);
  }

  /// 移除窗口及其页签，返回这些页签（连接仍由调用方关闭）。
  List<SessionTab> removeWindow(String windowId) {
    final window = find(windowId);
    if (window == null) return const [];
    windows.remove(window);
    final removed = <SessionTab>[];
    for (final id in window.tabIds) {
      final tab = tabs.remove(id);
      if (tab != null) removed.add(tab);
    }
    return removed;
  }
}
