// A17.8: the TV background — sources, files (blurred once), the layer and
// the preview.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/custom_background_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/background/custom_background.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_pages.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_preview.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_files.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_sources.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';

import '../qa_capture.dart';
import '../support.dart';

/// A small red PNG, drawn here.
Future<List<int>> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = const ui.Color(0xFFFF0000));
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  group('sources', () {
    test('no source of the removed kind is offered (D-032)', () {
      final names = [
        for (final group in tvRandomGroups)
          for (final source in group.sources) '${source.name} ${source.url}',
      ];
      for (final word in ['黑丝', '白丝', '美女', '美囡', '性感', 'heisi', 'baisi', 'meinv', 'sexy']) {
        expect(names.where((name) => name.contains(word)), isEmpty, reason: word);
      }
      expect(tvRandomGroups.map((group) => group.id), isNot(contains('sexy')));
    });

    test("a random answer: the picture's address wherever the JSON puts it; JSON APIs are asked with their key", () {
      expect(randomPictureUrl({'code': 200, 'data': 'https://a/1.jpg'}), 'https://a/1.jpg');
      expect(
        randomPictureUrl({
          'data': [
            {'url': 'https://a/2.jpg'},
          ],
        }),
        'https://a/2.jpg',
      );
      expect(randomPictureUrl({'image_url': 'https://a/3.jpg'}), 'https://a/3.jpg');
      expect(randomPictureUrl({'msg': 'nope'}), isNull);
      final keyed = tvRandomGroups.expand((group) => group.sources).firstWhere((source) => source.apiKey != null);
      final url = randomRequestUrl(keyed);
      expect(url.queryParameters['type'], 'json');
      expect(url.queryParameters['apiKey'], keyed.apiKey);
    });

    test('Wallhaven is asked for safe-for-work pictures only', () {
      for (final category in const WallhavenWallpapers().categories) {
        expect(WallhavenWallpapers.queryOf(category.id, 1)['purity'], '100');
        expect(WallhavenWallpapers.queryOf(category.id, 1)['categories'], isNot(endsWith('1')), reason: 'no people');
      }
    });

    test('the stored background: defaults as pure_live_TV, unknown names fall back', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final wallpaper = TvWallpaper.of(store.settings);
      expect(wallpaper.active, isFalse);
      expect((wallpaper.fit, wallpaper.mask, wallpaper.blur), (BoxFit.cover, 0.35, 0.0));
      expect(tvWallpaperFitOf('nope'), BoxFit.cover);
      expect(TvWallpaperKind.of('nope'), TvWallpaperKind.none);
      expect(tvGradients.first.gradient.colors, tvGradients.first.colors);
    });
  });

  group('files', () {
    late Directory folder;
    late LiveStore live;
    late TvWallpaperStore store;
    setUp(() async {
      folder = Directory.systemTemp.createTempSync('tv_wallpaper');
      live = await LiveStore.memory(cipher: FakeCipher());
      store = TvWallpaperStore(
        settings: live.settings,
        files: TvWallpaperFiles(folder: Future.value(folder), http: NoNetworkHttp()),
      );
    });
    tearDown(() async {
      await live.close();
      folder.deleteSync(recursive: true);
    });

    testWidgets('a picture is blurred once when set; the old files go; clearing removes them', (tester) async {
      await tester.runAsync(() async {
        final picked = File('${folder.path}/scratch-1.png')..writeAsBytesSync(await _png());
        await store.setPicture(Uri.file(picked.path).toString(), fit: BoxFit.contain, mask: 0.6, blur: 4);
        final now = store.current;
        expect(now.kind, TvWallpaperKind.image);
        expect((now.fit, now.mask, now.blur), (BoxFit.contain, 0.6, 4.0));
        expect(now.value, contains('blur-'));
        expect(File(now.value).existsSync(), isTrue);
        expect(store.files.blurs, 1);

        await store.setBlur(4);
        expect(store.files.blurs, 1, reason: 'the same blur is not computed again');
        await store.setBlur(0);
        expect(store.current.value, picked.path, reason: 'no blur: the picture itself');

        await store.setGradient(tvGradients.first.name);
        expect(store.current.kind, TvWallpaperKind.gradient);
        expect(folder.listSync(), isEmpty, reason: 'the picture files went');
        await store.clear();
        expect(store.current.active, isFalse);
      });
    });
  });

  group('screen', () {
    // Lets the store answer (real time) and the frames run.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Unmounted before the store closes (as tv_test's _close).
    Future<void> close(WidgetTester tester, AppServices services) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(services.close);
    }

    Future<(AppServices, TvWallpaperStore)> pump(
      WidgetTester tester,
      Widget child, {
      Future<File?> Function()? picker,
      bool tvMode = false,
    }) async {
      await prepareQaFonts(tester);
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(testServices))!;
      if (tvMode) await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'tv'));
      await tester.runAsync(loadStrings);
      final folder = Directory.systemTemp.createTempSync('tv_wallpaper');
      addTearDown(() => folder.deleteSync(recursive: true));
      final store = TvWallpaperStore(
        settings: services.store.settings,
        files: TvWallpaperFiles(folder: Future.value(folder), http: NoNetworkHttp()),
      );
      final scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            tvWallpaperStoreProvider.overrideWithValue(store),
            if (picker != null) customBackgroundPickerProvider.overrideWithValue(picker),
          ],
          child: MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
                child: TvTheme(
                  palette: TvPalette.of(scheme),
                  child: Scaffold(body: child),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (services, store);
    }

    testWidgets('TV local images use bounded owned copies, preserve blur originals and keep source files on clear', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('tv_local_background_source_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = File('${directory.path}/source.png')..writeAsBytesSync((await tester.runAsync(_png))!);
      final bytes = source.readAsBytesSync();
      File? selected = source;
      var picks = 0;
      final (services, store) = await pump(
        tester,
        const TvWallpaperSettingsPage(),
        picker: () async {
          picks++;
          return selected;
        },
      );
      addTearDown(() => close(tester, services));
      final previousToast = AppNavigator.toast;
      final errors = <String>[];
      AppNavigator.toast = errors.add;
      addTearDown(() => AppNavigator.toast = previousToast);
      Future<void> drive(Future<void> operation) async {
        var finished = false;
        Object? failure;
        final observed = operation.then(
          (_) => finished = true,
          onError: (Object error) {
            failure = error;
            finished = true;
          },
        );
        for (var i = 0; i < 10 && !finished; i++) {
          await tester.pump();
          await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        }
        expect(finished, isTrue, reason: 'native image and store work must settle');
        await observed;
        expect(failure, isNull);
      }

      await drive(services.store.settings.set(Settings.tvWallpaperBlur, 4));
      await tester.runAsync(() async {
        tester
            .widget<TvLinkRow>(find.byWidgetPredicate((w) => w is TvLinkRow && w.id == 'wallpaper-local-image'))
            .onTap();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      for (var i = 0; i < 3 && store.current.kind != TvWallpaperKind.image; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await tester.pump();
      }
      expect(picks, 1);
      expect(errors, isEmpty);
      expect(store.current.kind, TvWallpaperKind.image);
      final original = File(Uri.parse(store.current.source).toFilePath());
      expect(original.parent.path, (await store.files.folder).path);
      expect(original.existsSync(), isTrue, reason: 'changing blur must retain the imported original');
      expect(File(store.current.value).existsSync(), isTrue);
      await drive(store.setBlur(0));
      expect(store.current.value, original.path);
      selected = null;
      await tester.tap(find.byKey(const ValueKey('tv-setting-wallpaper-local-image')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump();
      expect(store.current.value, original.path, reason: 'cancelled picker keeps the selected image');
      await drive(store.clear());
      expect(original.existsSync(), isFalse);
      expect(source.readAsBytesSync(), bytes);
    });

    testWidgets('shared appearance entry opens TV wallpaper controls when TV mode is selected', (tester) async {
      final (services, _) = await pump(tester, const CustomBackgroundPage(), tvMode: true);
      await tester.pump();
      expect(find.byKey(const ValueKey('tv-settings-page-wallpaper')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-custom-background')), findsNothing);
      await close(tester, services);
    });

    testWidgets('the layer: nothing without a background, a colour with one', (tester) async {
      final (services, store) = await pump(tester, const TvWallpaperLayer());
      expect(find.byKey(const ValueKey('tv-wallpaper')), findsNothing);
      unawaited(store.setColor('FF2AD39A'));
      await settle(tester);
      expect(find.byKey(const ValueKey('tv-wallpaper')), findsOneWidget);
      final box = tester.widget<ColoredBox>(
        find.descendant(of: find.byKey(const ValueKey('tv-wallpaper')), matching: find.byType(ColoredBox)).first,
      );
      expect(box.color, const Color(0xFF2AD39A));
      expect(services.store.settings.get(Settings.tvWallpaperKind), 'color');
      await close(tester, services);
    });

    testWidgets('the preview: what is tried there is not kept by Back; "设为背景" keeps it with the picture', (
      tester,
    ) async {
      final folder = Directory.systemTemp.createTempSync('tv_preview');
      addTearDown(() => folder.deleteSync(recursive: true));
      final picture = File('${folder.path}/a.png')..writeAsBytesSync((await tester.runAsync(_png))!);
      final items = [TvWallpaperItem(url: Uri.file(picture.path).toString())];
      final (services, store) = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push<void>(MaterialPageRoute(builder: (_) => TvWallpaperPreviewPage(items: items, index: 0))),
            child: const Text('打开'),
          ),
        ),
      );
      final settings = services.store.settings;

      Future<void> open() async {
        await tester.tap(find.text('打开'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await open();
      expect(find.text('遮罩 · 35%'), findsOneWidget);
      // The veil to 60 % from its button.
      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-mask')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('60%'));
      await tester.pump();
      await tester.tap(find.text('60%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('遮罩 · 60%'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('tv-wallpaper-preview')), findsNothing);
      expect(settings.get(Settings.tvWallpaperMask), 0.35, reason: 'Back keeps the background as it was');
      expect(settings.get(Settings.tvWallpaperKind), 'none');

      // Immersive: OK leaves it.
      await open();
      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-immersive-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('tv-wallpaper-immersive')), findsOneWidget);
      await press(LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('tv-wallpaper-immersive')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-mask')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('60%'));
      await tester.pump();
      await tester.tap(find.text('60%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-apply')));
      for (var i = 0; i < 4; i++) {
        await settle(tester);
      }
      expect(store.current.kind, TvWallpaperKind.image);
      expect(store.current.mask, 0.6);
      expect(store.current.source, items.first.url);
      await close(tester, services);
    });

    testWidgets('issue #38: failed wallpaper retry stays reachable and visibly starts a new request', (tester) async {
      final library = _PendingLibrary();
      const category = TvWallpaperCategory('all', 'tv_wallpaper_bing_daily');
      final (services, _) = await pump(tester, TvWallpaperGridPage(library: library, category: category));
      expect(library.pending, hasLength(1));
      library.pending[0].completeError(const TransportFailure('wallpaper', TransportReason.connect));
      await settle(tester);
      expect(find.text('重试'), findsOneWidget);
      bool retryFocused() => Focus.of(tester.element(find.text('重试'))).hasPrimaryFocus;
      expect(retryFocused(), isTrue, reason: 'the asynchronously appearing action takes focus');
      await captureQaFrame(tester, 'wallpaper-retry-failure');
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(retryFocused(), isTrue, reason: 'a one-action failure page must not lose its remote focus');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(library.pending, hasLength(2));
      expect(find.text('重试'), findsNothing, reason: 'pending retry replaces the stale failure with loading');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await captureQaFrame(tester, 'wallpaper-retry-loading');
      // Repeated OK while loading never queues duplicate requests.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(library.pending, hasLength(2));
      library.pending[1].completeError(const TransportFailure('wallpaper', TransportReason.connect));
      await settle(tester);
      expect(retryFocused(), isTrue, reason: 'a repeated failure restores retry focus');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(library.pending, hasLength(3));
      library.pending[2].complete(const []);
      await settle(tester);
      expect(find.text('重试'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await close(tester, services);
    });

    testWidgets('a library page takes the focus on its first picture once it loads', (tester) async {
      const category = TvWallpaperCategory('all', 'tv_wallpaper_bing_daily');
      final (services, _) = await pump(tester, const TvWallpaperGridPage(library: _Library(), category: category));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('tv-wallpaper-item-0')), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key,
        const ValueKey('tv-wallpaper-item-0'),
      );
      await close(tester, services);
    });
  });
}

final class _Library implements TvWallpaperLibrary {
  const new();

  @override
  String get id => 'test';

  @override
  String get nameKey => 'tv_wallpaper_bing';

  @override
  List<TvWallpaperCategory> get categories => const [];

  @override
  Future<List<TvWallpaperItem>> items(LiveHttp http, String category, int page) async => [
    if (page == 1)
      for (var n = 0; n < 6; n++) TvWallpaperItem(url: 'https://a.example/$n.jpg'),
  ];
}

final class _PendingLibrary implements TvWallpaperLibrary {
  final List<Completer<List<TvWallpaperItem>>> pending = [];

  @override
  String get id => 'test';

  @override
  String get nameKey => 'tv_wallpaper_wallhaven';

  @override
  List<TvWallpaperCategory> get categories => const [];

  @override
  Future<List<TvWallpaperItem>> items(LiveHttp http, String category, int page) {
    final next = Completer<List<TvWallpaperItem>>();
    pending.add(next);
    return next.future;
  }
}
