import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_sources.dart';

/// The TV background's files (A17.8 h7) in [folder]: the picture or video
/// as fetched (`original-<hash>`), and a picture blurred once when it is set
/// (`blur-<hash>-<sigma>.png`), so nothing is blurred while drawing (UI.md
/// §9.3). Setting another background deletes the old files.
final class TvWallpaperFiles {
  /// Creates the files in [folder] (found once, by the first use).
  new({required this.folder, required this.http});

  /// The folder.
  final Future<Directory> folder;

  /// Fetches pictures and videos.
  final LiveHttp http;

  /// A short name of [text] (FNV-1a, 32 bits twice).
  static String _hash(String text) {
    var a = 0x811c9dc5;
    var b = 0x01000193;
    for (final byte in utf8.encode(text)) {
      a = ((a ^ byte) * 0x01000193) & 0xffffffff;
      b = ((b ^ byte) * 0x811c9dc5 + 7) & 0xffffffff;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}';
  }

  static String _extension(String url, String fallback) {
    final extension = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    return extension.length > 1 && extension.length <= 5 ? extension : fallback;
  }

  /// The file of [url] as fetched: a `file://` address is the file itself,
  /// anything else is downloaded once into the folder.
  Future<File> original(String url, {String fallback = '.jpg'}) async {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'file') return File(uri.toFilePath());
    final dir = await folder;
    final file = File(p.join(dir.path, 'original-${_hash(url)}${_extension(url, fallback)}'));
    if (file.existsSync() && file.lengthSync() > 0) return file;
    await http.download(LiveRequest.get(site: tvWallpaperSite, url: Uri.parse(url)), file.path);
    return file;
  }

  /// A file for a picture fetched before it is chosen (a random API's
  /// answer), whose address is `file://` of it.
  Future<File> scratch(List<int> bytes, String extension) async {
    final dir = await folder;
    final file = File(p.join(dir.path, 'scratch-${DateTime.now().microsecondsSinceEpoch}$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// [picture] blurred by [sigma] once, as a PNG at most 1920 wide; the
  /// picture itself when [sigma] is 0. Counted in [blurs] (tests).
  Future<File> blurred(File picture, double sigma) async {
    if (sigma <= 0) return picture;
    try {
      return await _blur(picture, sigma);
    } on Object {
      // A picture this engine cannot decode is shown as it is.
      return picture;
    }
  }

  Future<File> _blur(File picture, double sigma) async {
    final dir = await folder;
    final file = File(p.join(dir.path, 'blur-${_hash(picture.path)}-${sigma.round()}.png'));
    if (file.existsSync() && file.lengthSync() > 0) return file;
    blurs++;
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(await picture.readAsBytes()),
      getTargetSize: (width, height) => width > 1920
          ? ui.TargetImageSize(width: 1920, height: (height * 1920 / width).round())
          : const ui.TargetImageSize(),
    );
    ui.Image? image;
    ui.Image? blurredImage;
    ui.Picture? commands;
    try {
      image = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImage(
        image,
        ui.Offset.zero,
        ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
      );
      commands = recorder.endRecording();
      blurredImage = await commands.toImage(image.width, image.height);
      final png = await blurredImage.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return picture;
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file;
    } finally {
      commands?.dispose();
      blurredImage?.dispose();
      image?.dispose();
      codec.dispose();
    }
  }

  /// Pictures blurred so far.
  int blurs = 0;

  /// Deletes every file but [keep].
  Future<void> keepOnly(Set<String> keep) async {
    final dir = await folder;
    if (!dir.existsSync()) return;
    for (final entry in dir.listSync()) {
      if (entry is File && !keep.contains(entry.path)) {
        try {
          entry.deleteSync();
        } on FileSystemException {
          // In use; next time.
        }
      }
    }
  }
}

/// Sets and changes the TV background (A17.8 h1, h3, h7).
final class TvWallpaperStore {
  /// Creates the store over [settings] and [files].
  const new({required this.settings, required this.files});

  /// The settings.
  final SettingsStore settings;

  /// The files.
  final TvWallpaperFiles files;

  /// The background now.
  TvWallpaper get current => TvWallpaper.of(settings);

  Future<void> _set(TvWallpaperKind kind, String value, {String source = ''}) async {
    await settings.set(Settings.tvWallpaperSource, source);
    await settings.set(Settings.tvWallpaperValue, value);
    await settings.set(Settings.tvWallpaperKind, kind.name);
  }

  /// One colour (no files kept).
  Future<void> setColor(String hex) async {
    await _set(TvWallpaperKind.color, hex);
    await files.keepOnly(const {});
  }

  /// A built-in gradient (no files kept).
  Future<void> setGradient(String name) async {
    await _set(TvWallpaperKind.gradient, name);
    await files.keepOnly(const {});
  }

  /// The picture at [url] with how it was previewed (h3: set together).
  Future<void> setPicture(String url, {required BoxFit fit, required double mask, required double blur}) async {
    final original = await files.original(url);
    final shown = await files.blurred(original, blur);
    await settings.set(Settings.tvWallpaperFit, fit.name);
    await settings.set(Settings.tvWallpaperMask, mask);
    await settings.set(Settings.tvWallpaperBlur, blur);
    await _set(TvWallpaperKind.image, shown.path, source: url);
    await files.keepOnly({original.path, shown.path});
  }

  /// The video at [url], downloaded once (h1; it plays a file, which cannot
  /// half-open).
  Future<void> setVideo(String url) async {
    final file = await files.original(url, fallback: '.mp4');
    await _set(TvWallpaperKind.video, file.path, source: url);
    await files.keepOnly({file.path});
  }

  /// A new blur for the picture now (the settings page's slider): blurred
  /// again from the file as fetched.
  Future<void> setBlur(double blur) async {
    await settings.set(Settings.tvWallpaperBlur, blur);
    final now = current;
    if (now.kind != TvWallpaperKind.image || now.source.isEmpty) return;
    final original = await files.original(now.source);
    final shown = await files.blurred(original, blur);
    await settings.set(Settings.tvWallpaperValue, shown.path);
    await files.keepOnly({original.path, shown.path});
  }

  /// Back to the theme's plain colour (h5); the files go.
  Future<void> clear() async {
    await _set(TvWallpaperKind.none, '');
    await files.keepOnly(const {});
  }
}
