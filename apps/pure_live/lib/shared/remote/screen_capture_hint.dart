/// Application-only capture banner preference; never changes OS privacy UI.
enum ScreenCaptureHint {
  /// Full text and a local stop button.
  full,

  /// Small, labelled stop button.
  compact,

  /// No in-app overlay; the remote-control page retains its stop button.
  hidden;

  /// Invalid imported values retain the visible default.
  static ScreenCaptureHint of(String value) => values.asNameMap()[value] ?? full;
}
