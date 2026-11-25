import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_pages.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_files.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_sources.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// Fetches one picture of [source]: a picture answer is kept as a file (the
/// next request would answer another), a JSON one gives its address.
Future<TvWallpaperItem> fetchRandomPicture(LiveHttp http, TvRandomSource source, TvWallpaperStore store) async {
  final response = await http.send(LiveRequest.get(site: tvWallpaperSite, url: randomRequestUrl(source)));
  if (response.status != 200) throw HttpStatusFailure.of(tvWallpaperSite, response);
  final type = response.header('content-type') ?? '';
  if (type.startsWith('image/')) {
    final extension = switch (type) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      _ => '.jpg',
    };
    final file = await store.files.scratch(response.bytes, extension);
    return TvWallpaperItem(url: Uri.file(file.path).toString());
  }
  final url = randomPictureUrl(jsonDecode(utf8.decode(response.bytes, allowMalformed: true)));
  if (url == null) throw const FormatException('no picture in the answer');
  return TvWallpaperItem(url: url);
}

/// A picture before it becomes the background (A17.8 h2, h3, h6): the fill,
/// veil and blur tried here apply to the preview only and are kept with the
/// picture by "设为背景" (Back leaves the background as it was). "沉浸式"
/// hides the buttons; there ←→ and ↑↓ change the picture, OK or Back show
/// the buttons again.
class TvWallpaperPreviewPage extends ConsumerStatefulWidget {
  /// Previews [items], starting at [index].
  const new({required this.items, required this.index, super.key}) : source = null;

  /// Previews pictures of a random API, one fetched at a time.
  const new random({required TvRandomSource this.source, super.key}) : items = const [], index = 0;

  /// The pictures of a library.
  final List<TvWallpaperItem> items;

  /// The one shown first.
  final int index;

  /// The random API, if any.
  final TvRandomSource? source;

  @override
  ConsumerState<TvWallpaperPreviewPage> createState() => _TvWallpaperPreviewPageState();
}

class _TvWallpaperPreviewPageState extends ConsumerState<TvWallpaperPreviewPage> {
  late final List<TvWallpaperItem> _items = List.of(widget.items);
  late int _index = widget.index;
  late final TvWallpaper _now = ref.read(tvWallpaperStoreProvider).current;
  late BoxFit _fit = _now.fit;
  late double _mask = _now.mask;
  late double _blur = _now.blur;
  bool _immersive = false;
  bool _fetching = false;
  bool _applying = false;
  Object? _error;
  final FocusNode _immersiveNode = FocusNode(debugLabel: 'tv wallpaper immersive');
  final FocusNode _apply = FocusNode(debugLabel: 'tv wallpaper apply');

  TvWallpaperItem? get _item => _index < _items.length ? _items[_index] : null;

  @override
  void initState() {
    super.initState();
    if (widget.source != null) unawaited(_fetch());
  }

  @override
  void dispose() {
    _immersiveNode.dispose();
    _apply.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final source = widget.source;
    if (source == null || _fetching) return;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final item = await fetchRandomPicture(
        ref.read(appServicesProvider).http,
        source,
        ref.read(tvWallpaperStoreProvider),
      );
      if (!mounted) return;
      setState(() {
        _items.add(item);
        _index = _items.length - 1;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _step(int by) {
    final next = _index + by;
    if (next >= _items.length && widget.source != null) {
      unawaited(_fetch());
      return;
    }
    if (next < 0 || next >= _items.length) return;
    setState(() => _index = next);
  }

  void _setImmersive(bool on) {
    setState(() => _immersive = on);
    WidgetsBinding.instance.addPostFrameCallback((_) => (on ? _immersiveNode : _apply).requestFocus());
  }

  Future<void> _set() async {
    final item = _item;
    if (item == null || _applying) return;
    setState(() => _applying = true);
    AppNavigator.toast(i18n('tv_wallpaper_downloading'));
    try {
      await ref.read(tvWallpaperStoreProvider).setPicture(item.url, fit: _fit, mask: _mask, blur: _blur);
      AppNavigator.toast(i18n('tv_wallpaper_applied'));
      if (mounted) Navigator.of(context).pop();
    } on Object {
      AppNavigator.toast(i18n('tv_wallpaper_failed'));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _choose<T>(String title, List<TvChoice<T>> options, T current, void Function(T value) set) async {
    final value = await showTvChoice<T>(context, title: title, options: options, current: current);
    if (value != null && mounted) setState(() => set(value));
  }

  KeyEventResult _immersiveKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowUp:
        _step(-1);
      case LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowDown:
        _step(1);
      case LogicalKeyboardKey.select || LogicalKeyboardKey.enter || LogicalKeyboardKey.escape:
        _setImmersive(false);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final item = _item;
    Widget picture;
    if (item == null) {
      picture = Center(
        child: _error != null
            ? Text(i18n('tv_wallpaper_load_failed'), style: scale.font(TvTextSize.body, color: palette.text))
            : const CircularProgressIndicator(),
      );
    } else {
      final uri = Uri.tryParse(item.url);
      picture = uri != null && uri.scheme == 'file'
          ? Image.file(File(uri.toFilePath()), key: ValueKey(item.url), fit: _fit, gaplessPlayback: true)
          : Image.network(
              item.url,
              key: ValueKey(item.url),
              fit: _fit,
              gaplessPlayback: true,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) => Center(
                child: Text(i18n('tv_wallpaper_load_failed'), style: scale.font(TvTextSize.body, color: palette.text)),
              ),
            );
      // The preview only: the background is blurred once when set (h7).
      if (_blur > 0) {
        picture = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          child: picture,
        );
      }
    }
    return PopScope(
      canPop: !_immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setImmersive(false);
      },
      child: Scaffold(
        key: const ValueKey('tv-wallpaper-preview'),
        backgroundColor: OnVideoColors.ground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            ColoredBox(color: OnVideoColors.ground.withValues(alpha: _mask)),
            if (_immersive)
              Focus(
                focusNode: _immersiveNode,
                autofocus: true,
                onKeyEvent: _immersiveKey,
                child: const SizedBox.expand(key: ValueKey('tv-wallpaper-immersive')),
              )
            else
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(scale.px(96), 0, scale.px(96), scale.px(56)),
                  child: Wrap(
                    spacing: scale.px(16),
                    runSpacing: scale.px(12),
                    alignment: WrapAlignment.center,
                    children: [
                      TvButton(
                        key: const ValueKey('tv-wallpaper-fit'),
                        label: '${i18n('tv_wallpaper_fit')} · ${tvFitLabel(_fit)}',
                        onTap: () => unawaited(
                          _choose<BoxFit>(
                            i18n('tv_wallpaper_fit'),
                            [for (final (fit, key) in tvWallpaperFits) TvChoice(value: fit, label: i18n(key))],
                            _fit,
                            (value) => _fit = value,
                          ),
                        ),
                      ),
                      TvButton(
                        key: const ValueKey('tv-wallpaper-mask'),
                        label: '${i18n('tv_wallpaper_mask')} · ${(_mask * 100).round()}%',
                        onTap: () => unawaited(
                          _choose<double>(
                            i18n('tv_wallpaper_mask'),
                            [for (var step = 0; step <= 10; step++) TvChoice(value: step / 10, label: '${step * 10}%')],
                            (_mask * 10).round() / 10,
                            (value) => _mask = value,
                          ),
                        ),
                      ),
                      TvButton(
                        key: const ValueKey('tv-wallpaper-blur'),
                        label: '${i18n('tv_wallpaper_blur')} · ${tvBlurLabel(_blur)}',
                        onTap: () => unawaited(
                          _choose<double>(
                            i18n('tv_wallpaper_blur'),
                            [for (final value in tvWallpaperBlurs) TvChoice(value: value, label: tvBlurLabel(value))],
                            _blur,
                            (value) => _blur = value,
                          ),
                        ),
                      ),
                      if (widget.source != null)
                        TvButton(
                          key: const ValueKey('tv-wallpaper-next'),
                          label: i18n('tv_wallpaper_next'),
                          onTap: _fetching ? null : () => _step(1),
                        ),
                      TvButton(
                        key: const ValueKey('tv-wallpaper-immersive-button'),
                        label: i18n('tv_wallpaper_immersive'),
                        onTap: item == null ? null : () => _setImmersive(true),
                      ),
                      TvButton(
                        key: const ValueKey('tv-wallpaper-apply'),
                        focusNode: _apply,
                        autofocus: true,
                        kind: TvButtonKind.primary,
                        label: i18n('tv_wallpaper_set'),
                        onTap: item == null || _applying ? null : () => unawaited(_set()),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
