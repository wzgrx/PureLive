import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';

/// The common control surface of official replay players. Platform resolution
/// and progress stores remain independent; live playback is never reused as VOD.
abstract class ArchivePlaybackController extends ChangeNotifier {
  /// Completes after asynchronous native disposal, so another decoder can resume.
  Future<void> get retirement;

  /// Page-owned native playback session.
  PlaybackSession get session;

  /// Current metadata without media credentials.
  ArchiveVideo? get video;

  /// Current input position, including a pending seek.
  Duration get position;

  /// Server-offered renditions.
  List<ArchiveQuality> get qualities;

  /// Selected rendition id.
  String? get qualityId;

  /// Related segments, when the platform provides them.
  List<ArchiveVideo> get segments => const [];

  /// Resolution or quality change in progress.
  bool get busy;

  /// Failure translated by the shared player.
  Object? get error;

  /// Whether this source exposes a verified comment timeline.
  bool get supportsDanmaku => false;

  /// Current comment visibility.
  bool get danmakuVisible => false;

  /// Timeline messages, not live-room comments from a different broadcast.
  Stream<LiveMessage> get messages => const Stream.empty();

  /// Timeline clears after seeking.
  Stream<LiveRetraction> get retractions => const Stream.empty();

  /// Opens an official video id and optional position.
  Future<void> open(String id, {Duration? start});

  /// Selects a permitted quality without losing position.
  Future<void> selectQuality(String id);

  /// Seeks within the current recording.
  Future<void> seek(Duration position);

  /// Saves metadata and position only.
  Future<void> record();

  /// Toggles a supported comment timeline.
  void toggleDanmaku() {}
}
