import 'package:meta/meta.dart';

/// A failure a platform adapter reports, by kind.
///
/// Sealed so the interface and the recovery logic handle each kind by type,
/// never by message text. 3.x's adapters returned an offline-looking room or
/// a Chinese sentence instead, and a temporary error could end a recording.
@immutable
sealed class SiteError implements Exception {
  const new(this.site, [this.detail]);

  /// Platform id, for example `douyu`.
  final String site;

  /// Diagnostic detail for logs; never shown as UI copy.
  final String? detail;

  /// Whether retrying the same request later can succeed.
  bool get isTransient => false;

  /// Stable name of the kind, for logs and diagnostics.
  String get kind;

  @override
  String toString() => '$kind($site${detail == null ? '' : ': $detail'})';
}

/// The room or streamer does not exist.
final class NotFound extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'NotFound';
}

/// The content needs a signed-in account.
final class NeedsLogin extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'NeedsLogin';
}

/// The platform throttled the client.
final class RateLimited extends SiteError {
  /// Creates the error.
  const new(String site, {this.retryAfter, String? detail}) : super(site, detail);

  /// Suggested wait, when the platform gives one.
  final Duration? retryAfter;

  @override
  bool get isTransient => true;

  @override
  String get kind => 'RateLimited';
}

/// The platform refused the request as suspicious: a rejected signature, a
/// captcha, a stale cookie.
final class RiskControl extends SiteError {
  /// Creates the error.
  const new(String site, {this.cookieSuspect = false, String? detail}) : super(site, detail);

  /// Whether the user's stored cookie is the likely cause (ask to renew it).
  final bool cookieSuspect;

  @override
  String get kind => 'RiskControl';
}

/// The content is not available in the user's region.
final class RegionBlocked extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'RegionBlocked';
}

/// No playable stream right now: offline, a loop or replay without a stream,
/// or live without video.
final class StreamUnavailable extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]) : code = null;

  /// Creates a failure with a fixed reason safe for export.
  const new withCode(super.site, this.code, [super.detail]);

  /// A fixed reason, never a response, identifier or credential.
  final ApiFailureCode? code;

  @override
  String get kind => 'StreamUnavailable';
}

/// A link that no adapter recognises.
final class UnsupportedLink extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'UnsupportedLink';
}

/// Fixed, non-sensitive reasons for an API response failure. Unlike [SiteError.detail],
/// these may be included in an exported application log.
enum ApiFailureCode {
  /// The signing descriptor response was not a JSON object.
  douyuDescriptorJson,

  /// The descriptor endpoint returned a failed envelope or HTTP status.
  douyuDescriptorEnvelope,

  /// The signing descriptor lacked a required field.
  douyuDescriptorFields,

  /// The descriptor's hashing round count was outside its supported range.
  douyuDescriptorRounds,

  /// The descriptor was already expired or inside its safety margin.
  douyuDescriptorExpiry,

  /// The play response was not a JSON object.
  douyuPlayJson,

  /// The play response had no recognised error code.
  douyuPlayCode,

  /// The play response had no data object or a failed HTTP status.
  douyuPlayData,

  /// The play endpoint returned a nonzero platform status.
  douyuPlayUnavailable,

  /// The metadata response explicitly reported no pushed stream.
  douyuStreamNotPushed,

  /// The WebView cannot safely isolate a temporary visitor from account data.
  xiaohongshuVisitorIsolationUnavailable,
}

/// The response does not match the platform spec.
final class ApiChanged extends SiteError {
  /// Creates the error; [detail] should summarise the unexpected shape.
  const new(super.site, [super.detail]) : code = null;

  /// Creates a failure with a fixed reason safe for export.
  const new withCode(super.site, this.code, [super.detail]);

  /// A fixed reason, never a response, URL, identifier or credential.
  final ApiFailureCode? code;

  @override
  String get kind => 'ApiChanged';
}

/// The network failed before the platform answered.
final class NetworkFailure extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  bool get isTransient => true;

  @override
  String get kind => 'NetworkFailure';
}
