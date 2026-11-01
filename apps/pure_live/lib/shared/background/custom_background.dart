import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/services.dart';

/// Persisted phone/desktop background; TV keeps its existing wallpaper settings.
@immutable
final class CustomBackgroundConfig {
  /// Default is disabled and does not change the theme.
  const new({this.kind = 'none', this.file = '', this.color = 0xff172136, this.mask = 0.7, this.fit = 'cover'});

  /// Reads imported settings without allowing arbitrary local paths.
  factory fromJson(Map<String, Object?> value) {
    final kind = value['kind'];
    final file = value['file'];
    final color = value['color'];
    final mask = value['mask'];
    return .new(
      kind: const {'none', 'image', 'color'}.contains(kind) ? kind! as String : 'none',
      file: file is String && CustomBackgroundFiles.ownedName.hasMatch(file) ? file : '',
      color: color is int && color >= 0 && color <= 0xffffffff ? color | 0xff000000 : 0xff172136,
      mask: mask is num && mask.isFinite ? mask.toDouble().clamp(0, 1) : 0.7,
      fit: fits.contains(value['fit']) ? value['fit']! as String : 'cover',
    );
  }

  /// Shared supported image fitting modes for validation, UI and translations.
  static const Set<String> fits = {'cover', 'contain', 'fill'};

  /// none, image or color.
  final String kind;

  /// Only an app-owned basename, never the user's original file path.
  final String file;

  /// Opaque ARGB colour.
  final int color;

  /// Theme-coloured scrim preserving readable page contents.
  final double mask;

  /// Image fitting mode.
  final String fit;

  /// Stable settings representation.
  Map<String, Object?> toJson() => {'kind': kind, 'file': file, 'color': color, 'mask': mask, 'fit': fit};
}

/// Owned, bounded, static PNG copies; originals and unrelated files are untouched.
final class CustomBackgroundFiles {
  /// Uses only this application support folder.
  const new(this.folder);

  /// Private background directory.
  final Future<Directory> folder;

  /// The only filenames eligible for loading or deletion.
  static final RegExp ownedName = RegExp(r'^background-[0-9a-f]+\.png$');

  /// Encoded input limit, before decoding.
  static const int maxBytes = 20 * 1024 * 1024;

  /// Copies the first frame, at most 2560 pixels along either edge.
  Future<String> importImage(File source) async {
    if (await source.length() > maxBytes) throw const FormatException('Image too large');
    final collected = await source
        .openRead(0, maxBytes + 1)
        .fold(BytesBuilder(copy: false), (buffer, chunk) => buffer..add(chunk));
    final bytes = collected.takeBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) throw const FormatException('Image too large or empty');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0 || width * height > 80000000 || math.max(width, height) > 32768) {
        throw const FormatException('Image dimensions too large');
      }
      final factor = math.min(1, math.min(2560 / math.max(width, height), math.sqrt(6000000 / (width * height))));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * factor).floor()),
        targetHeight: math.max(1, (height * factor).floor()),
      );
      image = (await codec.getNextFrame()).image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw const FormatException('Image not decodable');
      final dir = await folder;
      await dir.create(recursive: true);
      final name = 'background-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}.png';
      await File(p.join(dir.path, name)).writeAsBytes(encoded.buffer.asUint8List(), flush: true);
      return name;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// Resolves only app-owned copies; a backup without its picture falls back.
  Future<File?> resolve(String name) async {
    if (!ownedName.hasMatch(name)) return null;
    final file = File(p.join((await folder).path, name));
    return file.existsSync() ? file : null;
  }

  /// Deletes only obsolete owned copies after settings have been saved.
  Future<void> keepOnly(String name) async {
    final dir = await folder;
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !ownedName.hasMatch(p.basename(entity.path)) || p.basename(entity.path) == name) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        /* A later replacement can retry. */
      }
    }
  }
}

/// Image selection is supplied by native plugins, and replaceable in tests.
final customBackgroundPickerProvider = Provider<Future<File?> Function()>(
  (ref) =>
      () async => null,
);

/// Private static image store.
final Provider<CustomBackgroundFiles> customBackgroundFilesProvider = Provider(
  (ref) => CustomBackgroundFiles(
    Future.value(Directory(p.join(ref.watch(appServicesProvider).dataRoot.path, 'custom_background'))),
  ),
);

final FutureProviderFamily<File?, String> _imageProvider = FutureProvider.family<File?, String>(
  (ref, name) => ref.watch(customBackgroundFilesProvider).resolve(name),
);

/// Paints under the navigator; panels/dialogs retain their accessible surfaces.
class CustomBackgroundFrame extends ConsumerWidget {
  /// Wraps every phone and desktop page; never owns media decoders.
  const new({required this.child, super.key});

  /// Application navigator and floating layers.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = CustomBackgroundConfig.fromJson(watchSetting(ref, Settings.customBackground));
    final file = config.kind == 'image' ? ref.watch(_imageProvider(config.file)).asData?.value : null;
    if (config.kind == 'none' || (config.kind == 'image' && file == null)) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(scaffoldBackgroundColor: OnVideoColors.clear),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: theme.scaffoldBackgroundColor),
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (config.kind == 'color')
                      ColoredBox(color: Color(config.color))
                    else
                      Image.file(
                        file!,
                        fit: BoxFit.values.asNameMap()[config.fit],
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ColoredBox(color: theme.colorScheme.surface.withValues(alpha: config.mask)),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
