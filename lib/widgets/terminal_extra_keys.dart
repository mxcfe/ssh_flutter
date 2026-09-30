import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Sticky Ctrl/Alt/Shift for soft-keyboard combinations (e.g. Ctrl+C).
class TerminalModifiers extends TerminalInputHandler with ChangeNotifier {
  TerminalModifiers([this._inner = defaultInputHandler]);

  final TerminalInputHandler _inner;

  bool ctrl = false;
  bool alt = false;
  bool shift = false;

  void toggleCtrl() {
    ctrl = !ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    alt = !alt;
    notifyListeners();
  }

  void toggleShift() {
    shift = !shift;
    notifyListeners();
  }

  void clear() {
    if (!ctrl && !alt && !shift) return;
    ctrl = false;
    alt = false;
    shift = false;
    notifyListeners();
  }

  @override
  String? call(TerminalKeyboardEvent event) {
    final injected = ctrl || alt || shift;
    final output = _inner.call(
      event.copyWith(
        ctrl: event.ctrl || ctrl,
        alt: event.alt || alt,
        shift: event.shift || shift,
      ),
    );
    // One-shot: release sticky modifiers after a real key is sent.
    if (output != null && injected) {
      clear();
    }
    return output;
  }
}

enum _ExtraKeyKind { key, text, toggleCtrl, toggleAlt, toggleFn, keyboard }

class _ExtraKey {
  const _ExtraKey.key(this.label, this.terminalKey)
      : kind = _ExtraKeyKind.key,
        text = null;

  const _ExtraKey.text(this.label, this.text)
      : kind = _ExtraKeyKind.text,
        terminalKey = null;

  const _ExtraKey.toggleCtrl()
      : label = 'CTRL',
        kind = _ExtraKeyKind.toggleCtrl,
        terminalKey = null,
        text = null;

  const _ExtraKey.toggleAlt()
      : label = 'ALT',
        kind = _ExtraKeyKind.toggleAlt,
        terminalKey = null,
        text = null;

  const _ExtraKey.toggleFn()
      : label = 'FN',
        kind = _ExtraKeyKind.toggleFn,
        terminalKey = null,
        text = null;

  const _ExtraKey.keyboard()
      : label = '⌨',
        kind = _ExtraKeyKind.keyboard,
        terminalKey = null,
        text = null;

  final String label;
  final _ExtraKeyKind kind;
  final TerminalKey? terminalKey;
  final String? text;
}

/// Termux-style extra key bar for Android terminal sessions.
class TerminalExtraKeysBar extends StatefulWidget {
  const TerminalExtraKeysBar({
    super.key,
    required this.terminal,
    required this.modifiers,
    required this.onToggleKeyboard,
  });

  final Terminal terminal;
  final TerminalModifiers modifiers;
  final VoidCallback onToggleKeyboard;

  @override
  State<TerminalExtraKeysBar> createState() => _TerminalExtraKeysBarState();
}

class _TerminalExtraKeysBarState extends State<TerminalExtraKeysBar> {
  bool _fnPage = false;

  static const _mainRows = <List<_ExtraKey>>[
    [
      _ExtraKey.key('ESC', TerminalKey.escape),
      _ExtraKey.text('/', '/'),
      _ExtraKey.text('|', '|'),
      _ExtraKey.text('-', '-'),
      _ExtraKey.key('HOME', TerminalKey.home),
      _ExtraKey.key('↑', TerminalKey.arrowUp),
      _ExtraKey.key('END', TerminalKey.end),
      _ExtraKey.key('PGUP', TerminalKey.pageUp),
      _ExtraKey.toggleFn(),
    ],
    [
      _ExtraKey.key('TAB', TerminalKey.tab),
      _ExtraKey.toggleCtrl(),
      _ExtraKey.toggleAlt(),
      _ExtraKey.key('←', TerminalKey.arrowLeft),
      _ExtraKey.key('↓', TerminalKey.arrowDown),
      _ExtraKey.key('→', TerminalKey.arrowRight),
      _ExtraKey.key('PGDN', TerminalKey.pageDown),
      _ExtraKey.keyboard(),
    ],
  ];

  static const _fnRows = <List<_ExtraKey>>[
    [
      _ExtraKey.key('F1', TerminalKey.f1),
      _ExtraKey.key('F2', TerminalKey.f2),
      _ExtraKey.key('F3', TerminalKey.f3),
      _ExtraKey.key('F4', TerminalKey.f4),
      _ExtraKey.key('F5', TerminalKey.f5),
      _ExtraKey.key('F6', TerminalKey.f6),
      _ExtraKey.toggleFn(),
    ],
    [
      _ExtraKey.key('F7', TerminalKey.f7),
      _ExtraKey.key('F8', TerminalKey.f8),
      _ExtraKey.key('F9', TerminalKey.f9),
      _ExtraKey.key('F10', TerminalKey.f10),
      _ExtraKey.key('F11', TerminalKey.f11),
      _ExtraKey.key('F12', TerminalKey.f12),
      _ExtraKey.keyboard(),
    ],
  ];

  void _onPressed(_ExtraKey key) {
    switch (key.kind) {
      case _ExtraKeyKind.toggleCtrl:
        widget.modifiers.toggleCtrl();
      case _ExtraKeyKind.toggleAlt:
        widget.modifiers.toggleAlt();
      case _ExtraKeyKind.toggleFn:
        setState(() => _fnPage = !_fnPage);
      case _ExtraKeyKind.keyboard:
        widget.onToggleKeyboard();
      case _ExtraKeyKind.key:
        widget.terminal.keyInput(
          key.terminalKey!,
          ctrl: widget.modifiers.ctrl,
          alt: widget.modifiers.alt,
          shift: widget.modifiers.shift,
        );
        // keyInput goes through modifiers handler which one-shots; if handler
        // is not used for somehow, still clear sticky state for bar presses.
        if (widget.modifiers.ctrl ||
            widget.modifiers.alt ||
            widget.modifiers.shift) {
          // Already cleared inside TerminalModifiers.call when output != null.
        }
      case _ExtraKeyKind.text:
        final text = key.text!;
        if (widget.modifiers.ctrl || widget.modifiers.alt) {
          final code = text.codeUnitAt(0);
          widget.terminal.charInput(
            code,
            ctrl: widget.modifiers.ctrl,
            alt: widget.modifiers.alt,
          );
          widget.modifiers.clear();
        } else {
          widget.terminal.textInput(text);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _fnPage ? _fnRows : _mainRows;

    return Material(
      color: const Color(0xFF21262D),
      child: ListenableBuilder(
        listenable: widget.modifiers,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows) ...[
                  Row(
                    children: [
                      for (final key in row)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: _ExtraKeyButton(
                              label: key.label,
                              selected: switch (key.kind) {
                                _ExtraKeyKind.toggleCtrl =>
                                  widget.modifiers.ctrl,
                                _ExtraKeyKind.toggleAlt =>
                                  widget.modifiers.alt,
                                _ExtraKeyKind.toggleFn => _fnPage,
                                _ => false,
                              },
                              onPressed: () => _onPressed(key),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExtraKeyButton extends StatelessWidget {
  const _ExtraKeyButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF388BFD) : const Color(0xFF30363D),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFE6EDF3),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
