import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/background/custom_background.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_preview.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_files.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_sources.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

void _push(BuildContext context, String name, WidgetBuilder builder) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: builder,
  ),
);

/// The words of [blur] ("关闭" or the sigma).
String tvBlurLabel(double blur) => blur <= 0 ? i18n('tv_wallpaper_blur_off') : '${blur.round()}';

/// The words of [fit].
String tvFitLabel(BoxFit fit) {
  for (final (value, key) in tvWallpaperFits) {
    if (value == fit) return i18n(key);
  }
  return fit.name;
}

/// "背景设置" (A17.8 h1, h4, h5; from the TV settings): where the
/// background comes from — colours and gradients, the library, random
/// pictures, a video — then how it shows (fill, veil, blur as slider and
/// choice rows) and "清除背景", which asks first with the focus on "取消".
class TvWallpaperSettingsPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(tvWallpaperStoreProvider);
    final settings = ref.read(storeProvider).settings;
    final wallpaper = watchTvWallpaper(ref);
    final blur = watchSetting(ref, Settings.tvWallpaperBlur);
    return TvSettingsScaffold(
      pageKey: const ValueKey('tv-settings-page-wallpaper'),
      title: i18n('tv_wallpaper'),
      child: TvSettingsColumn(
        children: [
          TvSettingsGroup(
            title: i18n('tv_wallpaper_sources'),
            children: [
              const _LocalWallpaperRow(),
              TvLinkRow(
                id: 'wallpaper-solid',
                icon: TvIcons.wallpaperSolid,
                title: i18n('tv_wallpaper_solid'),
                subtitle: i18n('tv_wallpaper_solid_desc'),
                onTap: () => _push(context, 'tv-wallpaper-solid', (_) => const TvWallpaperSolidPage()),
              ),
              TvLinkRow(
                id: 'wallpaper-library',
                icon: TvIcons.wallpaperLibrary,
                title: i18n('tv_wallpaper_library'),
                subtitle: i18n('tv_wallpaper_library_desc'),
                onTap: () => _push(context, 'tv-wallpaper-library', (_) => const TvWallpaperLibraryPage()),
              ),
              TvLinkRow(
                id: 'wallpaper-api',
                icon: TvIcons.wallpaperRandom,
                title: i18n('tv_wallpaper_api'),
                subtitle: i18n('tv_wallpaper_api_desc'),
                onTap: () => _push(context, 'tv-wallpaper-api', (_) => const TvWallpaperApiPage()),
              ),
              TvLinkRow(
                id: 'wallpaper-video',
                icon: TvIcons.wallpaperVideo,
                title: i18n('tv_wallpaper_video'),
                subtitle: i18n('tv_wallpaper_video_desc'),
                onTap: () => unawaited(_video(context, store)),
              ),
            ],
          ),
          TvSettingsGroup(
            title: i18n('tv_wallpaper_display'),
            children: [
              TvChoiceRow<BoxFit>(
                id: 'wallpaper-fit',
                icon: TvIcons.wallpaperFit,
                title: i18n('tv_wallpaper_fit'),
                value: wallpaper.fit,
                options: [for (final (fit, key) in tvWallpaperFits) TvChoice(value: fit, label: i18n(key))],
                onChanged: (fit) => settings.set(Settings.tvWallpaperFit, fit.name),
              ),
              TvSliderRow(
                id: 'wallpaper-mask',
                icon: TvIcons.wallpaperMask,
                title: i18n('tv_wallpaper_mask'),
                value: wallpaper.mask,
                min: 0,
                max: 1,
                step: 0.05,
                label: '${(wallpaper.mask * 100).round()}%',
                onChanged: (value) => unawaited(settings.set(Settings.tvWallpaperMask, (value * 20).round() / 20)),
              ),
              TvChoiceRow<double>(
                id: 'wallpaper-blur',
                icon: TvIcons.wallpaperBlur,
                title: i18n('tv_wallpaper_blur'),
                subtitle: wallpaper.kind == TvWallpaperKind.video ? i18n('tv_wallpaper_blur_video') : null,
                value: blur,
                options: [for (final value in tvWallpaperBlurs) TvChoice(value: value, label: tvBlurLabel(value))],
                onChanged: (value) {
                  if (wallpaper.kind == TvWallpaperKind.video) {
                    AppNavigator.toast(i18n('tv_wallpaper_blur_video'));
                    return;
                  }
                  unawaited(store.setBlur(value));
                },
              ),
            ],
          ),
          TvSettingsGroup(
            children: [
              TvLinkRow(
                id: 'wallpaper-clear',
                icon: TvIcons.delete,
                title: i18n('tv_wallpaper_clear'),
                subtitle: wallpaper.active ? null : i18n('tv_wallpaper_none'),
                onTap: () async {
                  final clear = await showTvConfirm(
                    context,
                    title: i18n('tv_wallpaper_clear'),
                    message: i18n('tv_wallpaper_clear_confirm'),
                    confirmLabel: i18n('tv_wallpaper_clear_action'),
                    danger: true,
                  );
                  if (clear) await store.clear();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _video(BuildContext context, TvWallpaperStore store) async {
    final url = await TvTextInput.prompt(
      context,
      title: i18n('tv_wallpaper_video'),
      hint: i18n('tv_wallpaper_video_hint'),
      text: store.current.kind == TvWallpaperKind.video ? store.current.source : '',
    );
    final address = url?.trim() ?? '';
    if (address.isEmpty) return;
    if (!(Uri.tryParse(address)?.isScheme('http') ?? false) && !(Uri.tryParse(address)?.isScheme('https') ?? false)) {
      AppNavigator.toast(i18n('tv_wallpaper_video_bad'));
      return;
    }
    AppNavigator.toast(i18n('tv_wallpaper_downloading'));
    try {
      await store.setVideo(address);
      AppNavigator.toast(i18n('tv_wallpaper_applied'));
    } on Object {
      AppNavigator.toast(i18n('tv_wallpaper_failed'));
    }
  }
}

class _LocalWallpaperRow extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_LocalWallpaperRow> createState() => _LocalWallpaperRowState();
}

class _LocalWallpaperRowState extends ConsumerState<_LocalWallpaperRow> {
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    final store = ref.read(tvWallpaperStoreProvider);
    final picker = ref.read(customBackgroundPickerProvider);
    setState(() => _busy = true);
    String? imported;
    try {
      final source = await picker();
      if (source == null || !mounted) return;
      final name = await CustomBackgroundFiles(store.files.folder).importImage(source);
      imported = name;
      if (!mounted) return;
      final file = (await CustomBackgroundFiles(store.files.folder).resolve(name))!;
      final current = store.current;
      await store.setPicture(file.uri.toString(), fit: current.fit, mask: current.mask, blur: current.blur);
    } on Object {
      if (mounted) AppNavigator.toast(i18n('custom_background_failed'));
    } finally {
      if (imported != null) {
        // Remove only this import if it was never selected. Existing wallpaper
        // originals and pre-blurred copies belong to the wallpaper store.
        final current = store.current;
        final file = await CustomBackgroundFiles(store.files.folder).resolve(imported);
        if (file != null && current.value != file.path && current.source != file.uri.toString()) {
          try {
            await file.delete();
          } on Object {
            // A later replacement can remove an in-use generated copy.
          }
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TvLinkRow(
    id: 'wallpaper-local-image',
    icon: TvIcons.wallpaperLibrary,
    title: i18n('custom_background_image'),
    subtitle: i18n(_busy ? 'refresh_loading' : 'custom_background_image_desc'),
    onTap: () => unawaited(_pick()),
  );
}

/// "纯色和渐变" (A17.8 h1): the common colours, then the gradients; OK sets
/// one at once; the one in use says "✓ 当前".
class TvWallpaperSolidPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(tvWallpaperStoreProvider);
    final wallpaper = watchTvWallpaper(ref);
    final swatches = [
      for (final color in LiveSwatches.common) (kind: TvWallpaperKind.color, value: colorHex(color)),
      for (final gradient in tvGradients) (kind: TvWallpaperKind.gradient, value: gradient.name),
    ];
    return TvSettingsScaffold(
      pageKey: const ValueKey('tv-wallpaper-solid'),
      title: i18n('tv_wallpaper_solid'),
      child: TvGrid(
        itemCount: swatches.length,
        columns: 6,
        aspectRatio: 16 / 9,
        itemBuilder: (context, index, node, onKey) {
          final swatch = swatches[index];
          final current = wallpaper.kind == swatch.kind && wallpaper.value == swatch.value;
          return TvFocusable(
            key: ValueKey('tv-wallpaper-swatch-$index'),
            focusNode: node,
            onKey: onKey,
            onTap: () => unawaited(
              swatch.kind == TvWallpaperKind.color ? store.setColor(swatch.value) : store.setGradient(swatch.value),
            ),
            builder: (context, focused) => _Swatch(
              color: swatch.kind == TvWallpaperKind.color ? parseColorHex(swatch.value) : null,
              gradient: swatch.kind == TvWallpaperKind.gradient ? tvGradientOf(swatch.value)?.gradient : null,
              current: current,
            ),
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const new({required this.current, this.color, this.gradient});

  final Color? color;
  final Gradient? gradient;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
      ),
      child: current ? const Align(alignment: Alignment.bottomRight, child: TvCurrentMark()) : null,
    );
  }
}

/// "✓ 当前" on the picture in use (A17.8 h8).
class TvCurrentMark extends StatelessWidget {
  /// Creates the mark.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Padding(
      padding: EdgeInsets.all(scale.px(8)),
      child: DecoratedBox(
        key: const ValueKey('tv-wallpaper-current'),
        decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(scale.px(TvRadius.pill))),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: scale.px(12), vertical: scale.px(4)),
          child: Text(
            i18n('tv_wallpaper_current'),
            style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.onAccent),
          ),
        ),
      ),
    );
  }
}

/// "壁纸库" (A17.8 h1): each library with its categories as rows.
class TvWallpaperLibraryPage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context) => TvSettingsScaffold(
    pageKey: const ValueKey('tv-wallpaper-library'),
    title: i18n('tv_wallpaper_library'),
    child: TvSettingsColumn(
      children: [
        for (final library in tvWallpaperLibraries)
          TvSettingsGroup(
            title: i18n(library.nameKey),
            children: [
              for (final category in library.categories)
                TvLinkRow(
                  id: 'library-${library.id}-${category.id}',
                  title: i18n(category.nameKey),
                  onTap: () => _push(
                    context,
                    'tv-wallpaper-grid',
                    (_) => TvWallpaperGridPage(library: library, category: category),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

/// A category's pictures in a grid of four (A17.8 h1, h8), a page at a time;
/// OK previews one.
class TvWallpaperGridPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({required this.library, required this.category, super.key});

  /// The library.
  final TvWallpaperLibrary library;

  /// The category.
  final TvWallpaperCategory category;

  @override
  ConsumerState<TvWallpaperGridPage> createState() => _TvWallpaperGridPageState();
}

class _TvWallpaperGridPageState extends ConsumerState<TvWallpaperGridPage> {
  final GlobalKey<TvGridState> _grid = GlobalKey();
  final List<TvWallpaperItem> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_more());
  }

  Future<void> _more() async {
    if (_loading || _end) return;
    setState(() {
      _loading = true;
      // A retry must visibly replace the old failure while it is pending.
      _error = null;
    });
    try {
      final next = await widget.library.items(ref.read(appServicesProvider).http, widget.category.id, _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        _items.addAll(next);
        _end = next.isEmpty;
        _error = null;
      });
      // The first page takes the focus on its first picture.
      if (_page == 1 && next.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _grid.currentState?.enter();
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = watchTvWallpaper(ref);
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final Widget body;
    if (_items.isEmpty) {
      body = _error != null
          ? TvStatusView.failure(_error, onRetry: () => unawaited(_more()), autofocus: true)
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : TvStatusView(icon: TvIcons.noResults, title: i18n('tv_wallpaper_empty'));
    } else {
      body = TvGrid(
        key: _grid,
        itemCount: _items.length,
        columns: 4,
        aspectRatio: 16 / 9,
        onEndReached: () => unawaited(_more()),
        itemBuilder: (context, index, node, onKey) {
          final item = _items[index];
          return TvFocusable(
            key: ValueKey('tv-wallpaper-item-$index'),
            focusNode: node,
            onKey: onKey,
            onTap: () =>
                _push(context, 'tv-wallpaper-preview', (_) => TvWallpaperPreviewPage(items: _items, index: index)),
            builder: (context, focused) => ClipRRect(
              borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: palette.card),
                  Image.network(item.thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  if (wallpaper.source == item.url)
                    const Align(alignment: Alignment.bottomRight, child: TvCurrentMark()),
                ],
              ),
            ),
          );
        },
      );
    }
    return TvSettingsScaffold(
      pageKey: const ValueKey('tv-wallpaper-grid'),
      title: '${i18n(widget.library.nameKey)} · ${i18n(widget.category.nameKey)}',
      child: body,
    );
  }
}

/// "随机壁纸" (A17.8 h1): the groups of random APIs, each with its sources;
/// OK on a source fetches one picture and previews it ("换一张" fetches
/// another).
class TvWallpaperApiPage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context) => TvSettingsScaffold(
    pageKey: const ValueKey('tv-wallpaper-api'),
    title: i18n('tv_wallpaper_api'),
    child: TvSettingsColumn(
      children: [
        for (final group in tvRandomGroups)
          TvSettingsGroup(
            title: i18n(group.nameKey),
            children: [
              for (final (index, source) in group.sources.indexed)
                TvLinkRow(
                  id: 'api-${group.id}-$index',
                  title: source.name,
                  subtitle: Uri.tryParse(source.url)?.host,
                  onTap: () =>
                      _push(context, 'tv-wallpaper-preview', (_) => TvWallpaperPreviewPage.random(source: source)),
                ),
            ],
          ),
      ],
    ),
  );
}
