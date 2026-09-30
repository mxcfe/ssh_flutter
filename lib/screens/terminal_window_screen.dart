import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_layout.dart';
import '../services/ssh_session.dart';
import '../widgets/sftp_browser.dart';
import '../widgets/terminal_view.dart';
import '../windows/desktop_sessions.dart';

/// 一个系统窗口里的终端/SFTP 页签。
class TerminalWindowScreen extends StatelessWidget {
  const TerminalWindowScreen({super.key, required this.windowId});

  final String windowId;

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<DesktopSessions>();
    final window = sessions.layout.find(windowId);
    if (window == null) {
      return const SizedBox.shrink();
    }

    var tabIndex = window.tabIds.indexOf(window.activeTabId);
    if (tabIndex < 0) tabIndex = 0;

    return Stack(
      children: [
        Scaffold(
          body: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: _TabStrip(window: window),
              ),
              Expanded(
                child: IndexedStack(
                  index: tabIndex,
                  sizing: StackFit.expand,
                  children: [
                    for (final tabId in window.tabIds)
                      _SessionPane(
                        key: ValueKey(tabId),
                        windowId: window.id,
                        tabId: tabId,
                        active: tabId == window.activeTabId,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: sessions.drag,
          builder: (context, _) {
            final drag = sessions.drag;
            final dropping = drag.hoverWindowId == window.id &&
                drag.sourceWindowId != null &&
                drag.sourceWindowId != window.id;
            final local = drag.localPosition;
            return Stack(
              children: [
                if (dropping)
                  const Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: _DropHint(),
                  ),
                if (drag.sourceWindowId == window.id && local != null)
                  Positioned(
                    left: local.dx + 12,
                    top: local.dy + 12,
                    child: IgnorePointer(
                      child: _DragGhost(label: drag.label ?? ''),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.window});

  final SessionWindow window;

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<DesktopSessions>();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final tabId in window.tabIds)
            _TabChip(
              key: ValueKey(tabId),
              windowId: window.id,
              tabId: tabId,
              label: _label(sessions, tabId),
              sftp: sessions.layout.tabs[tabId]?.session.mode ==
                  SessionMode.sftp,
              selected: tabId == window.activeTabId,
              canDetach: window.tabIds.length > 1,
            ),
        ],
      ),
    );
  }

  String _label(DesktopSessions sessions, String tabId) {
    final tab = sessions.layout.tabs[tabId];
    if (tab == null) return '会话';
    return sessions.tabLabel(tab);
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('松开放入此窗口'),
      ),
    );
  }
}

class _DragGhost extends StatelessWidget {
  const _DragGhost({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    super.key,
    required this.windowId,
    required this.tabId,
    required this.label,
    required this.sftp,
    required this.selected,
    required this.canDetach,
  });

  final String windowId;
  final String tabId;
  final String label;
  final bool sftp;
  final bool selected;
  final bool canDetach;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  static const double _slop = 8;
  Offset? _down;
  bool _dragging = false;

  void _onPointerDown(PointerDownEvent event) {
    if ((event.buttons & kPrimaryButton) == 0) return;
    _down = event.position;
    _dragging = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _down;
    if (origin == null) return;
    final sessions = context.read<DesktopSessions>();
    if (!_dragging && (event.position - origin).distance >= _slop) {
      _dragging = true;
      sessions.beginTabDrag(
        windowId: widget.windowId,
        tabId: widget.tabId,
        label: widget.label,
        localPosition: event.position,
      );
    }
    if (_dragging) {
      sessions.updateTabDrag(event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final sessions = context.read<DesktopSessions>();
    if (_dragging) {
      sessions.finishTabDrag();
    } else if (_down != null) {
      sessions.activateTab(widget.windowId, widget.tabId);
    }
    _down = null;
    _dragging = false;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_dragging) {
      context.read<DesktopSessions>().finishTabDrag();
    }
    _down = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<DesktopSessions>();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: widget.selected
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onSecondaryTapUp: (details) => _showMenu(context, details, sessions),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerCancel,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.sftp ? Icons.folder_open : Icons.terminal,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: ListenableBuilder(
                              listenable: sessions.drag,
                              builder: (context, _) {
                                final faded = sessions.drag.tabId == widget.tabId;
                                return Opacity(
                                  opacity: faded ? 0.45 : 1,
                                  child: Text(
                                    widget.label,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: '关闭',
                    onPressed: () =>
                        sessions.closeTab(widget.windowId, widget.tabId),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    TapUpDetails details,
    DesktopSessions sessions,
  ) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        if (widget.canDetach)
          const PopupMenuItem(value: 'detach', child: Text('拆出到新窗口')),
        const PopupMenuItem(value: 'close', child: Text('关闭')),
      ],
    );
    if (!context.mounted || value == null) return;
    if (value == 'detach') {
      sessions.detachTab(widget.windowId, widget.tabId);
    } else if (value == 'close') {
      await sessions.closeTab(widget.windowId, widget.tabId);
    }
  }
}

class _SessionPane extends StatelessWidget {
  const _SessionPane({
    super.key,
    required this.windowId,
    required this.tabId,
    required this.active,
  });

  final String windowId;
  final String tabId;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<DesktopSessions>();
    final tab = sessions.layout.tabs[tabId];
    if (tab == null) return const SizedBox.shrink();
    return ChangeNotifierProvider<SshSession>.value(
      value: tab.session,
      child: _PaneBody(
        tabId: tabId,
        active: active,
        onClose: () => sessions.closeTab(windowId, tabId),
      ),
    );
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({
    required this.tabId,
    required this.active,
    required this.onClose,
  });

  final String tabId;
  final bool active;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SshSession>();
    if (!session.isConnected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(session.errorMessage ?? '连接已断开'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onClose, child: const Text('关闭')),
          ],
        ),
      );
    }
    final isTerminal =
        (session.mode ?? SessionMode.terminal) == SessionMode.terminal;
    final sessions = context.read<DesktopSessions>();
    return SafeArea(
      child: isTerminal
          ? AppTerminalView(
              active: active,
              shared: sessions.terminalFor(tabId, session),
            )
          : const SftpBrowser(),
    );
  }
}
