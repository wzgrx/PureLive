#ifndef RUNNER_PLAYBACK_KEYBOARD_H_
#define RUNNER_PLAYBACK_KEYBOARD_H_

#include <windows.h>
#include <imm.h>

// Owns only an association, never the IME context or the user's input mode.
class PlaybackKeyboard {
 public:
  explicit PlaybackKeyboard(HWND view) : view_(view) {}
  ~PlaybackKeyboard() { SetEnabled(false); }
  void SetEnabled(bool enabled);
  bool enabled() const { return enabled_; }
  bool has_context() const;

 private:
  HWND view_ = nullptr;
  HIMC saved_context_ = nullptr;
  bool enabled_ = false;
};

#endif  // RUNNER_PLAYBACK_KEYBOARD_H_
