import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

import '../../support.dart';

final _now = DateTime(2026, 10, 25, 12);

LiveRoom _channel(String id, {String? epg}) =>
    LiveRoom(platform: SiteIds.iptv, roomId: id, title: id, epgId: epg, liveStatus: LiveStatus.live);

EpgProgramme _programme(String title) => EpgProgramme(
  channelId: 'guide-channel',
  sourceId: 'guide',
  start: _now.subtract(const Duration(minutes: 10)),
  stop: _now.add(const Duration(minutes: 50)),
  title: title,
);

final class _GuideRoom extends ChangeNotifier implements LiveRoomController {
  new(this.value);
  LiveRoom value;
  @override
  LiveRoom get room => value;
  @override
  EpgProgramme? get catchup => null;
  @override
  DateTime now() => _now;
  void change(LiveRoom room) {
    value = room;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadStrings);
  late LiveStore store;
  late ValueNotifier<_GuideRoom> active;
  late ValueNotifier<int> reveal;
  late _GuideRoom room;
  late int loads;

  Future<void> host(WidgetTester tester, Future<List<EpgProgramme>> Function() load) async {
    store = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
    await tester.runAsync(() => store.settings.set(Settings.selectedSourceId, 'guide'));
    room = _GuideRoom(_channel('first'));
    active = ValueNotifier(room);
    reveal = ValueNotifier(0);
    loads = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      reveal.dispose();
      active.dispose();
      room.dispose();
      await tester.runAsync(store.close);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: const LiveTheme().light,
          home: Scaffold(
            body: ValueListenableBuilder<_GuideRoom>(
              valueListenable: active,
              builder: (context, current, _) => IptvGuideView(
                controller: current,
                reveal: reveal,
                loader: (from, to) {
                  loads++;
                  return load();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('issue 48: late room guide metadata loads without rebuilding the view', (tester) async {
    await host(tester, () async => room.room.epgId == null ? [] : [_programme('Late guide')]);
    expect(find.byKey(const ValueKey('iptv-guide-empty')), findsOneWidget);
    room.change(_channel('first', epg: 'mapped'));
    await settle(tester);
    expect(find.text('Late guide'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets('issue 48: changing the selected guide refreshes the persistent view', (tester) async {
    await host(tester, () async => [_programme(store.settings.get(Settings.selectedSourceId))]);
    await tester.runAsync(() => store.settings.set(Settings.selectedSourceId, 'second guide'));
    await settle(tester);
    expect(find.text('second guide'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets('issue 48: room replacement rejects a late result from the previous room', (tester) async {
    final old = Completer<List<EpgProgramme>>();
    await host(tester, () => loads == 1 ? old.future : Future.value([_programme('New room')]));
    final next = _GuideRoom(_channel('second', epg: 'new'));
    addTearDown(next.dispose);
    active.value = next;
    await tester.pump();
    await tester.pump();
    old.complete([_programme('Stale room')]);
    await settle(tester);
    expect(find.text('New room'), findsOneWidget);
    expect(find.text('Stale room'), findsNothing);
  });

  testWidgets('issue 48: clearing the source rejects a pending result and removes old programmes', (tester) async {
    final old = Completer<List<EpgProgramme>>();
    await host(tester, () => old.future);
    await tester.runAsync(() => store.settings.set(Settings.selectedSourceId, ''));
    await settle(tester);
    old.complete([_programme('Stale source')]);
    await settle(tester);
    expect(find.byKey(const ValueKey('iptv-guide-unconfigured')), findsOneWidget);
    expect(find.text('Stale source'), findsNothing);
    expect(loads, 1);
  });

  testWidgets('issue 48: unrelated room notifications do not reload the guide', (tester) async {
    await host(tester, () async => [_programme('Stable')]);
    for (var n = 0; n < 10; n++) {
      room.change(room.room.copyWith(title: 'Title $n'));
    }
    await settle(tester);
    expect(loads, 1);
    expect(find.text('Stable'), findsOneWidget);
  });

  testWidgets('issue 48: reveal retries an empty result but does not queue duplicate pending reads', (tester) async {
    final pending = Completer<List<EpgProgramme>>();
    await host(tester, () => loads == 1 ? Future.value([]) : pending.future);
    reveal.value++;
    reveal.value++;
    await tester.pump();
    expect(loads, 2);
    pending.complete([_programme('Revealed')]);
    await settle(tester);
    expect(find.text('Revealed'), findsOneWidget);
  });
}
