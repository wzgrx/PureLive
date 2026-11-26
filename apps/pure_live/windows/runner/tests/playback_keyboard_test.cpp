#include "playback_keyboard.h"
#include <iostream>
int main() {
  HWND window = CreateWindowExW(0, L"STATIC", L"PureLive native IME test", WS_OVERLAPPED,
      0, 0, 64, 64, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (!window) return 20;
  HIMC owned = ImmCreateContext();
  if (!owned) return 21;
  HIMC original = ImmAssociateContext(window, owned);
  bool passed = true;
  {
    PlaybackKeyboard keyboard(window);
    keyboard.SetEnabled(true);
    keyboard.SetEnabled(true);
    passed = passed && keyboard.enabled() && !keyboard.has_context();
    keyboard.SetEnabled(false);
    HIMC restored = ImmGetContext(window);
    passed = passed && !keyboard.enabled() && restored == owned;
    if (restored) ImmReleaseContext(window, restored);
    keyboard.SetEnabled(true);
  }
  HIMC restored = ImmGetContext(window);
  passed = passed && restored == owned;
  if (restored) ImmReleaseContext(window, restored);
  ImmAssociateContext(window, original);
  ImmDestroyContext(owned);
  DestroyWindow(window);
  std::cout << "window_context_detach_restore_and_destructor=" << passed << std::endl;
  return passed ? 0 : 10;
}
