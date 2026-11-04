import 'dart:convert';
import 'dart:typed_data';

/// The bounded MessagePack subset used by CC's public WebSocket protocol.
/// Packet headers are little-endian; MessagePack numbers/lengths are big-endian.
abstract final class MessagePack {
  /// Encodes outbound registration/join data using integer identity fields.
  static Uint8List encode(Object? value) {
    final out = BytesBuilder(copy: false);
    void number(int marker, int value, int width) {
      final b = ByteData(width);
      switch (width) {
        case 1:
          b.setUint8(0, value);
        case 2:
          b.setUint16(0, value);
        case 4:
          b.setUint32(0, value);
        case 8:
          b.setInt64(0, value);
      }
      out
        ..addByte(marker)
        ..add(b.buffer.asUint8List());
    }

    void write(Object? v, int depth) {
      if (depth > 16) throw const FormatException('MessagePack nesting');
      if (v == null) {
        out.addByte(0xc0);
      } else if (v is bool) {
        out.addByte(v ? 0xc3 : 0xc2);
      } else if (v is int) {
        if (v >= 0 && v < 128) {
          out.addByte(v);
        } else if (v >= -32 && v < 0) {
          out.addByte(v & 255);
        } else if (v >= 0 && v <= 255) {
          number(0xcc, v, 1);
        } else if (v >= 0 && v <= 65535) {
          number(0xcd, v, 2);
        } else if (v >= 0 && v <= 0xffffffff) {
          number(0xce, v, 4);
        } else {
          number(0xd3, v, 8);
        }
      } else if (v is String) {
        final b = utf8.encode(v);
        final n = b.length;
        if (n > 65535) throw const FormatException('MessagePack string');
        if (n < 32) {
          out.addByte(0xa0 | n);
        } else if (n <= 255) {
          number(0xd9, n, 1);
        } else {
          number(0xda, n, 2);
        }
        out.add(b);
      } else if (v is Map) {
        if (v.length > 4096) throw const FormatException('MessagePack map');
        if (v.length < 16) {
          out.addByte(0x80 | v.length);
        } else {
          number(0xde, v.length, 2);
        }
        for (final e in v.entries) {
          write(e.key, depth + 1);
          write(e.value, depth + 1);
        }
      } else if (v is List) {
        if (v.length > 4096) throw const FormatException('MessagePack list');
        if (v.length < 16) {
          out.addByte(0x90 | v.length);
        } else {
          number(0xdc, v.length, 2);
        }
        for (final x in v) {
          write(x, depth + 1);
        }
      } else {
        throw const FormatException('MessagePack value');
      }
    }

    write(value, 0);
    return out.takeBytes();
  }

  /// Rejects truncated, trailing, deeply nested and oversized collections.
  static Object? decode(Uint8List data) => _Reader(data).decode();
}

final class _Reader {
  new(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int at = 0;
  int nodes = 0;
  void need(int n) {
    if (n < 0 || at + n > bytes.length) throw const FormatException('MessagePack truncated');
  }

  int unsigned(int n) {
    need(n);
    final v = switch (n) {
      1 => data.getUint8(at),
      2 => data.getUint16(at),
      4 => data.getUint32(at),
      _ => data.getUint64(at),
    };
    at += n;
    return v;
  }

  int signed(int n) {
    need(n);
    final v = switch (n) {
      1 => data.getInt8(at),
      2 => data.getInt16(at),
      4 => data.getInt32(at),
      _ => data.getInt64(at),
    };
    at += n;
    return v;
  }

  Object? decode() {
    if (bytes.length > 1024 * 1024) throw const FormatException('MessagePack size');
    final v = read(0);
    if (at != bytes.length) throw const FormatException('MessagePack trailing');
    return v;
  }

  Object? read(int depth) {
    if (depth > 16 || ++nodes > 20000) throw const FormatException('MessagePack complexity');
    final tag = unsigned(1);
    if (tag <= 0x7f) return tag;
    if (tag >= 0xe0) return tag - 256;
    if (tag >= 0xa0 && tag <= 0xbf) return string(tag & 31);
    if (tag >= 0x90 && tag <= 0x9f) return array(tag & 15, depth);
    if (tag >= 0x80 && tag <= 0x8f) return map(tag & 15, depth);
    return switch (tag) {
      0xc0 => null,
      0xc2 => false,
      0xc3 => true,
      0xcc => unsigned(1),
      0xcd => unsigned(2),
      0xce => unsigned(4),
      0xcf => unsigned(8),
      0xd0 => signed(1),
      0xd1 => signed(2),
      0xd2 => signed(4),
      0xd3 => signed(8),
      0xca => floating(4),
      0xcb => floating(8),
      0xd9 => string(unsigned(1)),
      0xda => string(unsigned(2)),
      0xdb => string(unsigned(4)),
      0xdc => array(unsigned(2), depth),
      0xdd => array(unsigned(4), depth),
      0xde => map(unsigned(2), depth),
      0xdf => map(unsigned(4), depth),
      0xc4 => binary(unsigned(1)),
      0xc5 => binary(unsigned(2)),
      0xc6 => binary(unsigned(4)),
      _ => throw const FormatException('MessagePack unsupported tag'),
    };
  }

  double floating(int n) {
    need(n);
    final v = n == 4 ? data.getFloat32(at) : data.getFloat64(at);
    at += n;
    if (!v.isFinite) throw const FormatException('MessagePack nonfinite');
    return v;
  }

  String string(int n) {
    if (n > 65535) throw const FormatException('MessagePack string size');
    need(n);
    final v = utf8.decode(Uint8List.sublistView(bytes, at, at + n));
    at += n;
    return v;
  }

  Uint8List binary(int n) {
    if (n > 65535) throw const FormatException('MessagePack binary size');
    need(n);
    final v = Uint8List.sublistView(bytes, at, at + n);
    at += n;
    return v;
  }

  List<Object?> array(int n, int depth) {
    if (n > 4096) throw const FormatException('MessagePack array size');
    return [for (var i = 0; i < n; i++) read(depth + 1)];
  }

  Map<Object, Object?> map(int n, int depth) {
    if (n > 4096) throw const FormatException('MessagePack map size');
    final out = <Object, Object?>{};
    for (var i = 0; i < n; i++) {
      final k = read(depth + 1);
      if (k is! String && k is! int) throw const FormatException('MessagePack key');
      out[k!] = read(depth + 1);
    }
    return out;
  }
}
