import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/phone/tv_phone_dialogs.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';

/// Escape goes back one level on the TV interface (a keyboard on a box or a
/// computer); the remote's Back arrives as the system's back.
class TvBackIntent extends Intent {
  /// Creates the intent.
  const new();
}

/// What the whole TV interface sits in (below the app's theme, above the
/// navigator), the counterpart of pure_live_TV's app shell:
///
/// - directional navigation ([NavigationMode.directional]: disabled controls
///   stay reachable, sliders move only once selected);
/// - text lifted on panels below 1080 lines ([TvScale.legibilityLift]) on
///   top of the user's text size;
/// - the TV palette: the phone's dark colour roles from the app theme
///   ([TvTheme], docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c4; the app shows its dark theme on
///   the TV), whether focused items grow (`tvFocusZoom`), and the toast in
///   the TV's sizes (16, corners of 12, U.15a's toast);
/// - Escape as Back;
/// - a web address opened anywhere shows its code for a phone (most
///   televisions have no browser, A17.9 c14, c18).
class TvAppFrame extends ConsumerStatefulWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The navigator.
  final Widget child;

  @override
  ConsumerState<TvAppFrame> createState() => _TvAppFrameState();
}

class _TvAppFrameState extends ConsumerState<TvAppFrame> {
  // What opened addresses before (the phone's browser), kept to put back.
  late final Future<bool> Function(Uri uri) _openExternal;

  @override
  void initState() {
    super.initState();
    _openExternal = AppNavigator.openExternal;
    AppNavigator.openExternal = _showLink;
  }

  @override
  void dispose() {
    AppNavigator.openExternal = _openExternal;
    super.dispose();
  }

  Future<bool> _showLink(Uri uri) async {
    final context = AppNavigator.navigatorContext;
    if (context == null || !context.mounted) return await _openExternal(uri);
    await showTvLink(context, title: uri.host, url: uri.toString());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final media = MediaQuery.of(context);
    final lift = TvScale.legibilityLift(context);
    final theme = Theme.of(context);
    final palette = TvPalette.of(theme.colorScheme);
    final framed = MediaQuery(
      data: media.copyWith(
        navigationMode: NavigationMode.directional,
        textScaler: TextScaler.linear(media.textScaler.scale(1) * lift),
      ),
      child: Builder(
        builder: (context) {
          final scale = TvScale.of(context);
          return Theme(
            data: theme.copyWith(
              colorScheme: palette.scheme,
              snackBarTheme: theme.snackBarTheme.copyWith(
                behavior: SnackBarBehavior.floating,
                backgroundColor: palette.scheme.inverseSurface,
                contentTextStyle: scale.font(TvTextSize.body, color: palette.scheme.onInverseSurface),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(scale.px(TvRadius.card))),
                insetPadding: EdgeInsets.fromLTRB(scale.px(240), 0, scale.px(240), scale.px(48)),
              ),
            ),
            // "扫码到手机" for every TV page (the search's "用手机输入"), not
            // only for the phone's pages shown in the TV look.
            child: TvPhoneBridge(child: child),
          );
        },
      ),
    );
    return TvTheme(
      palette: palette,
      zoom: watchSetting(ref, Settings.tvFocusZoom),
      backdrop: watchTvWallpaper(ref).active,
      child: Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): TvBackIntent()},
        child: Actions(
          actions: {
            TvBackIntent: CallbackAction<TvBackIntent>(
              onInvoke: (_) {
                final navigator = AppNavigator.navigatorContext;
                if (navigator != null) Navigator.maybePop(navigator);
                return null;
              },
            ),
          },
          // The background under every TV page (A17.8 h1).
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: palette.background),
              const TvWallpaperLayer(),
              framed,
            ],
          ),
        ),
      ),
    );
  }
}
