// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:path/path.dart' as p;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Plugin for summoning a platform share sheet.
class MethodChannelShare extends SharePlatform {
  /// [MethodChannel] used to communicate with the platform side.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'dev.fluttercommunity.plus/share',
  );

  @override
  Future<ShareResult> share(ShareParams params) async {
    final paramsMap = await _toPlatformMap(params);
    final result =
        await channel.invokeMethod<String>('share', paramsMap) ??
        'dev.fluttercommunity.plus/share/unavailable';
    return ShareResult(result, _statusFromResult(result));
  }

  Future<Map<String, dynamic>> _toPlatformMap(ShareParams params) async {
    assert(
      params.text != null ||
          params.uri != null ||
          (params.files != null && params.files!.isNotEmpty),
      'At least one of text, uri or files must be provided',
    );
    final map = <String, dynamic>{
      if (params.text != null) 'text': params.text,
      if (params.subject != null) 'subject': params.subject,
      if (params.title != null) 'title': params.title,
      if (params.uri != null) 'uri': params.uri.toString(),
    };
    if (params.sharePositionOrigin != null) {
      map['originX'] = params.sharePositionOrigin!.left;
      map['originY'] = params.sharePositionOrigin!.top;
      map['originWidth'] = params.sharePositionOrigin!.width;
      map['originHeight'] = params.sharePositionOrigin!.height;
    }
    if (params.files != null) {
      final files = await _getFiles(params.files!, params.fileNameOverrides);
      map['paths'] = [for (final file in files) file.path];
      map['mimeTypes'] = [
        for (final file in files) _mimeTypeForPath(file.path),
      ];
    }
    if (params.excludedCupertinoActivities != null &&
        params.excludedCupertinoActivities!.isNotEmpty) {
      map['excludedCupertinoActivities'] = [
        for (final value in params.excludedCupertinoActivities!) value.value,
      ];
    }
    return map;
  }

  /// Native share channels require local paths. Scoped resources are copied by
  /// stream so a large document is never accumulated as one Dart byte buffer.
  Future<FileSystemXFile> _getFile(XFile file, {String? nameOverride}) async {
    if (file is FileSystemXFile && file.path.isNotEmpty) return file;
    final root = await getTemporaryDirectory();
    final directory = Directory(p.join(root.path, const Uuid().v4()));
    await directory.create(recursive: true);
    final suggested = nameOverride ?? await file.name();
    final filename = _safeName(suggested);
    final target = File(p.join(directory.path, filename));
    final sink = target.openWrite();
    try {
      await sink.addStream(file.openRead());
      await sink.close();
    } catch (_) {
      // addStream can already close its sink after a read failure.
      try {
        await sink.close();
      } catch (_) {
        // Preserve the original read error while still removing partial data.
      }
      await directory.delete(recursive: true);
      rethrow;
    }
    return FileSystemXFile(target.path);
  }

  static String _safeName(String? suggested) {
    final name = p.posix
        .basename((suggested ?? '').replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
    return name.isEmpty || name == '.' || name == '..'
        ? '${const Uuid().v4()}.bin'
        : name;
  }

  Future<List<FileSystemXFile>> _getFiles(
    List<XFile> files,
    List<String>? overrides,
  ) => Future.wait([
    for (var i = 0; i < files.length; i++)
      _getFile(files[i], nameOverride: overrides?.elementAt(i)),
  ]);

  static String _mimeTypeForPath(String path) =>
      lookupMimeType(path) ?? 'application/octet-stream';

  static ShareResultStatus _statusFromResult(String result) {
    switch (result) {
      case '':
        return ShareResultStatus.dismissed;
      case 'dev.fluttercommunity.plus/share/unavailable':
        return ShareResultStatus.unavailable;
      default:
        return ShareResultStatus.success;
    }
  }
}
