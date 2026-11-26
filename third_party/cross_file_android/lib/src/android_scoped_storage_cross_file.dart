// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'android_library.g.dart' as android;

/// Implementation of [PlatformScopedStorageXFile] for Android.
base class AndroidScopedStorageXFile extends PlatformScopedStorageXFile {
  /// Optional backends support deterministic stream-lifecycle regression tests.
  AndroidScopedStorageXFile(
    super.params, {
    android.DocumentFile? documentFile,
    android.ContentResolver? contentResolver,
  }) : _providedDocumentFile = documentFile,
       _providedContentResolver = contentResolver,
       super.implementation();

  final android.DocumentFile? _providedDocumentFile;
  final android.ContentResolver? _providedContentResolver;
  late final android.DocumentFile _documentFile =
      _providedDocumentFile ??
      android.DocumentFile.fromSingleUri(singleUri: params.uri);
  late final android.ContentResolver _contentResolver =
      _providedContentResolver ?? android.ContentResolver.instance;

  /// Maximum native buffer size for one streamed read.
  @visibleForTesting
  static const int maxByteArrayLen = 4 * 1024;

  @override
  Future<DateTime?> lastModified() async {
    final ms = await _documentFile.lastModified();
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<int?> length() async {
    final value = await _documentFile.length();
    return value == 0 ? null : value;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    if (start != null && start < 0)
      throw RangeError('`start` must be >= 0. start: $start');
    if (end != null && end <= (start ?? 0))
      throw RangeError('`end` must be greater than `start`.');
    final input = await _contentResolver.openInputStream(params.uri);
    if (input == null) throw NullInputStreamException(params.uri);
    try {
      var remaining = start ?? 0;
      while (remaining > 0) {
        final skipped = await input.skip(remaining);
        if (skipped > 0) {
          remaining -= skipped;
        } else {
          final discarded = await input.readBytes(
            min(remaining, maxByteArrayLen),
          );
          if (discarded.isEmpty) return;
          remaining -= discarded.length;
        }
      }
      var position = start ?? 0;
      while (end == null || position < end) {
        final request = end == null
            ? maxByteArrayLen
            : min(maxByteArrayLen, end - position);
        final bytes = await input.readBytes(request);
        if (bytes.isEmpty) break;
        position += bytes.length;
        yield bytes;
      }
    } finally {
      // EOF, bounded ranges, cancellation and native read failures all release
      // the actual Java stream immediately instead of relying on proxy GC.
      await input.close();
    }
  }

  @override
  Future<Uint8List> readAsBytes() async {
    final input = await _contentResolver.openInputStream(params.uri);
    if (input == null) throw NullInputStreamException(params.uri);
    try {
      return await input.readAllBytes();
    } finally {
      await input.close();
    }
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      encoding.decodeStream(openRead());
  @override
  Future<bool> canRead() => _documentFile.canRead();
  @override
  Future<bool> exists() async =>
      await _documentFile.exists() && await _documentFile.isFile();
  @override
  Future<String?> name() => _documentFile.getName();
  @override
  Future<void> dispose() async {}
}

/// The provider could not open a readable stream for this URI.
final class NullInputStreamException implements Exception {
  NullInputStreamException(this.uri);
  final String uri;
  @override
  String toString() =>
      'NullInputStreamException: Failed to get native InputStream from file with path: $uri. '
      'App may not have permissions to access file.';
}
