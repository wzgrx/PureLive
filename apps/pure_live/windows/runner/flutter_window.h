#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"
#include "playback_keyboard.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct DisplayModeSnapshot {
    std::wstring device_name;
    int width = 0;
    int height = 0;
    double current_refresh_rate = 0;
    double max_refresh_rate = 0;
    std::vector<double> supported_refresh_rates;
  };

  DisplayModeSnapshot ReadDisplayMode() const;
  flutter::EncodableValue EncodeDisplayMode(
      const DisplayModeSnapshot& snapshot) const;
  void RememberDisplayMode(const DisplayModeSnapshot& snapshot);
  void NotifyDisplayModeChanged(bool force = false);

  void StartStartupRecovery();
  void RecoverStartupSurface();
  // The frame callback may outlive the HWND/controller. It owns only this token.
  struct StartupCallback { HWND window = nullptr; };
  std::shared_ptr<StartupCallback> startup_callback_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> startup_channel_;
  bool startup_layout_ready_ = false;
  bool uninstall_ready_ = false;
  bool uninstall_requested_ = false;
  bool uninstall_sent_ = false;
  void DispatchUninstallShutdown();
  bool startup_frame_seen_ = false;
  bool startup_recovery_started_ = false;
  int startup_recovery_attempts_ = 0;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  // Prevents re-entrant parent-window messages from reaching a controller
  // whose internal FlutterWindowsView is already being destroyed.
  bool flutter_controller_destroying_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      display_mode_channel_;
  std::unique_ptr<PlaybackKeyboard> playback_keyboard_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> playback_keyboard_channel_;
  std::wstring last_display_device_;
  int last_display_width_ = 0;
  int last_display_height_ = 0;
  double last_display_refresh_rate_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
