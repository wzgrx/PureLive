#include "playback_keyboard.h"

void PlaybackKeyboard::SetEnabled(bool enabled) {
  if (enabled == enabled_ || !IsWindow(view_)) return;
  if (enabled) {
    // VK_PROCESSKEY is consumed by the Windows engine before Dart sees it.
    // Detach only this view while no EditableText owns keyboard input.
    saved_context_ = ImmAssociateContext(view_, nullptr);
  } else {
    ImmAssociateContext(view_, saved_context_);
    saved_context_ = nullptr;
  }
  enabled_ = enabled;
}

bool PlaybackKeyboard::has_context() const {
  if (!IsWindow(view_)) return false;
  HIMC context = ImmGetContext(view_);
  if (context) ImmReleaseContext(view_, context);
  return context != nullptr;
}
