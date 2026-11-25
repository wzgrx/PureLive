// Copyright (c) 2026 Predidit. MIT license.

import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart';

String? readNativeString(MPV mpv, Pointer<mpv_handle> handle, String property) {
  return using((arena) {
    final name = property.toNativeUtf8(allocator: arena);
    final value = mpv.mpv_get_property_string(handle, name.cast());
    if (value == nullptr) return null;
    try {
      return value.cast<Utf8>().toDartString();
    } finally {
      mpv.mpv_free(value.cast());
    }
  });
}

int? readNativeInt64(MPV mpv, Pointer<mpv_handle> handle, String property) {
  return using((arena) {
    final name = property.toNativeUtf8(allocator: arena);
    final value = arena<Int64>();
    final status = mpv.mpv_get_property(
      handle,
      name.cast(),
      mpv_format.MPV_FORMAT_INT64,
      value.cast(),
    );
    return status < 0 ? null : value.value;
  });
}

/// [copy] must finish synchronously and return no native views.
T? readNativeNode<T>(
  MPV mpv,
  Pointer<mpv_handle> handle,
  String property,
  T Function(mpv_node) copy,
) {
  return using((arena) {
    final name = property.toNativeUtf8(allocator: arena);
    final value = arena<mpv_node>();
    final status = mpv.mpv_get_property(
      handle,
      name.cast(),
      mpv_format.MPV_FORMAT_NODE,
      value.cast(),
    );
    if (status < 0) return null;
    try {
      return copy(value.ref);
    } finally {
      mpv.mpv_free_node_contents(value);
    }
  });
}

/// Copies borrowed audio/video fields into Dart-owned values.
final class NativeNodeMap {
  NativeNodeMap(Pointer<mpv_node> pointer) {
    if (pointer == nullptr) return;
    final node = pointer.ref;
    if (node.format != mpv_format.MPV_FORMAT_NODE_MAP ||
        node.u.list == nullptr) {
      return;
    }
    final list = node.u.list.ref;
    if (list.num <= 0 || list.keys == nullptr || list.values == nullptr) return;
    for (var i = 0; i < list.num; i++) {
      if (list.keys[i] == nullptr) continue;
      final key = list.keys[i].cast<Utf8>().toDartString();
      final value = list.values[i];
      switch (value.format) {
        case mpv_format.MPV_FORMAT_INT64:
          _values[key] = value.u.int64;
        case mpv_format.MPV_FORMAT_DOUBLE:
          _values[key] = value.u.double_;
        case mpv_format.MPV_FORMAT_STRING:
          if (value.u.string != nullptr) {
            _values[key] = value.u.string.cast<Utf8>().toDartString();
          }
      }
    }
  }

  final _values = <String, Object>{};

  T? get<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }
}

/// Copies bounded seekable-cache intervals while the mpv event owns the node.
List<({double start, double end})> copyNativeSeekRanges(
  Pointer<mpv_node> pointer,
) {
  mpv_node? member(mpv_node node, String key) {
    if (node.format != mpv_format.MPV_FORMAT_NODE_MAP || node.u.list == nullptr)
      return null;
    final map = node.u.list.ref;
    if (map.num < 0 ||
        map.num > 64 ||
        map.keys == nullptr ||
        map.values == nullptr)
      return null;
    for (var i = 0; i < map.num; i++) {
      final name = map.keys[i];
      if (name != nullptr && name.cast<Utf8>().toDartString() == key)
        return map.values[i];
    }
    return null;
  }

  double? number(mpv_node? value) {
    if (value == null) return null;
    final result = switch (value.format) {
      mpv_format.MPV_FORMAT_DOUBLE => value.u.double_,
      mpv_format.MPV_FORMAT_INT64 => value.u.int64.toDouble(),
      _ => null,
    };
    return result != null && result.isFinite ? result : null;
  }

  if (pointer == nullptr) return const [];
  final ranges = member(pointer.ref, 'seekable-ranges');
  if (ranges == null ||
      ranges.format != mpv_format.MPV_FORMAT_NODE_ARRAY ||
      ranges.u.list == nullptr)
    return const [];
  final list = ranges.u.list.ref;
  if (list.num < 0 || list.num > 16 || list.values == nullptr) return const [];
  final result = <({double start, double end})>[];
  for (var i = 0; i < list.num; i++) {
    final interval = list.values[i];
    final start = number(member(interval, 'start'));
    final end = number(member(interval, 'end'));
    if (start != null && end != null && end > start)
      result.add((start: start, end: end));
  }
  return List.unmodifiable(result);
}
