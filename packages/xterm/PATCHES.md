# xterm local patch

Based on pub.dev `xterm` 4.0.0.

## Changes

- `lib/src/ui/custom_text_edit.dart`: pass `viewId: View.maybeOf(context)?.viewId`
  into `TextInputConfiguration`, so Windows/Flutter TextInput client attaches
  correctly and IME (e.g. Chinese input) works.
- `lib/src/terminal_view.dart`: treat soft-keyboard `newline`/`send`/`go` as
  Enter; stop trimming inserted text so lone `\n` is not dropped.
- Mouse drag reporting for apps like tmux pane resize:
  - `button_state.dart`: add `motion` (button id `| 32`).
  - `reporter.dart` / `handler.dart`: emit motion for mouse modes 1002/1003.
  - `gesture_handler.dart` / `gesture_detector.dart`: forward drag as mouse
    motion when `PointerInput.drag` is enabled; send button-up on drag end
    (pan wins over tap). Hold Shift to keep local text selection instead.
  - Android/touch: pan accepts touch/stylus only while mouse-drag report mode
    is on; after touch-slop it wins over Scrollable (not on pointer-down, so
    taps still open the IME). Listener fallback for pointer move/up.
