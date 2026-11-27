/// The video codecs the player can be asked to prefer, and the names the
/// model, the settings and the platform adapters use for them.
///
/// The model (`LivePlayLine.codec`, `LivePlayQuality.codec`) spells them
/// `avc`, `hevc`, `av1` (and `vp9`, `vp8` where a platform names them);
/// the setting stores a preference of `auto`, `h264`, `h265`, `av1` or
/// `vp9`/`vp8`. `auto` keeps the platform's own order, as 3.x did before
/// "优先 H.264" existed.
abstract final class VideoCodecs {
  /// No preference: the platform's order.
  static const String auto = 'auto';

  /// H.264 (AVC), the most compatible one; the setting's default.
  static const String h264 = 'h264';

  /// H.265 (HEVC).
  static const String h265 = 'h265';

  /// AV1 (dav1d in the engine).
  static const String av1 = 'av1';

  /// VP9.
  static const String vp9 = 'vp9';

  /// VP8.
  static const String vp8 = 'vp8';

  /// Every value a preference may hold (the setting's `allowed` set).
  static const Set<String> preferences = {auto, h264, h265, av1, vp9, vp8};

  /// The codec of the model that [preference] asks for (`avc` for `h264`,
  /// `hevc` for `h265`); null for [auto] or an unknown name.
  static String? of(String preference) => switch (preference) {
    h264 || 'avc' => 'avc',
    h265 || 'hevc' => 'hevc',
    av1 => 'av1',
    vp9 => 'vp9',
    vp8 => 'vp8',
    _ => null,
  };

  /// The normalised model codec of a [codec] hint or line (`h264`, `h.265`
  /// and `av01` read as `avc`, `hevc` and `av1`); null when unknown.
  static String? normalize(String? codec) {
    final value = codec?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return switch (value.replaceAll(RegExp(r'[.\-_]'), '')) {
      'avc' || 'h264' || 'avc1' || 'h2641' => 'avc',
      'hevc' || 'h265' || 'hev1' || 'hvc1' || 'bytevc1' => 'hevc',
      'av1' || 'av01' => 'av1',
      'vp9' || 'vp09' => 'vp9',
      'vp8' || 'vp08' => 'vp8',
      _ => null,
    };
  }

  /// Whether [codec] is the one [preference] asks for; true for [auto], so
  /// callers that only reorder keep the platform's order.
  static bool matches(String? codec, String preference) {
    if (preference == auto) return true;
    final wanted = of(preference);
    return wanted != null && normalize(codec) == wanted;
  }

  /// Whether [codec] is known to be a codec other than the one
  /// [preference] asks for — the one thing a "优先视频编码" caller must move
  /// behind. An unknown [codec] (an HLS line, a quality without a hint) is
  /// not other: it may well be the wanted one, so it stays where it is.
  static bool knownOther(String? codec, String preference) {
    if (preference == auto) return false;
    final wanted = of(preference);
    final actual = normalize(codec);
    return wanted != null && actual != null && actual != wanted;
  }
}
