import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Schedules a notification at the next frame, or immediately without a binding.
void scheduleChatFlushForNextFrame(VoidCallback flush) {
  if (kDebugMode && BindingBase.debugBindingType() == null) {
    flush();
    return;
  }
  SchedulerBinding.instance
    ..scheduleFrameCallback((_) => flush())
    ..scheduleFrame();
}
