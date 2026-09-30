enum TerminalMouseButtonState {
  up,

  down,

  /// Pointer moved while a button is held (or any-event motion).
  /// Reported with button id `| 32` per the xterm mouse protocol.
  motion,
}
