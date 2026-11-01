import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/shared/remote/screen_capture_hint.dart';
import 'package:pure_live/shared/remote/screen_share.dart';

/// A real route covers the old room, including native/predictive Back handling.
class ScreenMirrorPage extends ConsumerStatefulWidget {
  /// Creates the single incoming mirror view.
  const new({super.key});

  @override
  ConsumerState<ScreenMirrorPage> createState() => _ScreenMirrorPageState();
}

class _ScreenMirrorPageState extends ConsumerState<ScreenMirrorPage> with RouteAware {
  late final ScreenShare _share;
  PageRoute<dynamic>? _route;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _share = ref.read(appServicesProvider).screenShare;
    _share.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _route)) {
      liveRouteObserver.unsubscribe(this);
      _route = route;
      liveRouteObserver.subscribe(this, route);
    }
    _closeEnded();
  }

  @override
  void didPopNext() => _closeEnded();

  void _changed() {
    if (mounted) setState(() {});
    _closeEnded();
  }

  void _closeEnded() {
    if (!mounted || _share.receiving || _closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closing = false;
      if (mounted && !_share.receiving && (_route?.isCurrent ?? false)) AppNavigator.back();
    });
  }

  @override
  void dispose() {
    liveRouteObserver.unsubscribe(this);
    _share.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) unawaited(_share.stop());
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_share.stop())},
      child: Scaffold(
        key: const ValueKey('screen-mirror-page'),
        backgroundColor: OnVideoColors.ground,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(i18n('screen_share_receiver')),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => unawaited(_share.stop()),
              child: Text(i18n('screen_share_stop')),
            ),
          ],
        ),
        body: _share.incoming == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      i18n('screen_share_connecting'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: OnVideoColors.foreground),
                    ),
                  ],
                ),
              )
            : _ScreenVideo(stream: _share.incoming!, onUnavailable: () => unawaited(_share.stop())),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              i18n('screen_share_restore'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: OnVideoColors.foreground),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ScreenVideo extends StatefulWidget {
  const new({required this.stream, required this.onUnavailable});
  final MediaStream stream;
  final VoidCallback onUnavailable;

  @override
  State<_ScreenVideo> createState() => _ScreenVideoState();
}

class _ScreenVideoState extends State<_ScreenVideo> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  late final Future<void> _ready;
  Timer? _firstFrame;
  bool _initialized = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _renderer.initialize();
      if (!mounted) return;
      _renderer.onFirstFrameRendered = () {
        _firstFrame?.cancel();
        if (mounted) setState(() => _shown = true);
      };
      _renderer.srcObject = widget.stream;
      setState(() => _initialized = true);
      _firstFrame = Timer(const Duration(seconds: 25), () {
        if (mounted && !_shown) widget.onUnavailable();
      });
    } on Object {
      if (mounted) widget.onUnavailable();
    }
  }

  @override
  void dispose() {
    _firstFrame?.cancel();
    _renderer.onFirstFrameRendered = null;
    unawaited(_ready.then((_) => _renderer.dispose()).catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_initialized) RTCVideoView(_renderer),
      if (!_shown) const Center(child: CircularProgressIndicator()),
    ],
  );
}

/// The visible Stop action remains available after the sender leaves settings.
class ScreenCaptureIndicator extends ConsumerWidget {
  /// Creates the app-local indicator, separate from Android's system indicator.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = ref.watch(appServicesProvider).screenShare;
    final hint = ScreenCaptureHint.of(watchSetting(ref, Settings.screenCaptureHint));
    return ScreenCaptureIndicatorView(share: share, hint: hint);
  }
}

/// Provider-independent banner with an always-local stop action.
class ScreenCaptureIndicatorView extends StatelessWidget {
  /// Creates the selected application-only presentation.
  const new({required this.share, required this.hint, super.key});

  /// The same owned session used by the remote-control page.
  final ScreenShare share;

  /// Banner visibility; consent remains visible in every mode.
  final ScreenCaptureHint hint;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: share,
      builder: (context, _) {
        if (!share.capturing && !share.consenting) return const SizedBox.shrink();
        if (hint == ScreenCaptureHint.hidden && !share.consenting) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                child: hint == ScreenCaptureHint.compact && !share.consenting
                    ? IconButton(
                        key: const ValueKey('screen-capture-compact-stop'),
                        tooltip: i18n('screen_share_stop'),
                        onPressed: () => unawaited(share.stop()),
                        icon: const Icon(Icons.stop_screen_share_outlined),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(i18n(share.consenting ? 'screen_share_consent' : 'screen_share_active')),
                            TextButton(
                              onPressed: () => unawaited(share.stop()),
                              child: Text(i18n('screen_share_stop')),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
