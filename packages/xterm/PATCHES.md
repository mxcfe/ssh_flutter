# xterm local patch

Based on pub.dev `xterm` 4.0.0.

## Changes

- `lib/src/ui/custom_text_edit.dart`: pass `viewId: View.maybeOf(context)?.viewId`
  into `TextInputConfiguration`, so Windows/Flutter TextInput client attaches
  correctly and IME (e.g. Chinese input) works.
