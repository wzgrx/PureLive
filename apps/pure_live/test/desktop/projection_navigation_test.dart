import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/desktop/projection_runtime.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

void main() {
  testWidgets('receiver changes rooms in one window and keeps a base route', (tester) async {
    final opened = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('receiver home')),
        GoRoute(
          path: RoutePath.kLivePlay,
          builder: (_, state) => _ReceiverRoom(args: state.extra! as LiveRoomArgs, opened: opened),
        ),
      ],
    );
    AppNavigator.router = router;
    addTearDown(() {
      AppNavigator.router = null;
      router.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    navigateProjectionRoom(LiveRoom(platform: 'iptv', roomId: 'one'));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);
    navigateProjectionRoom(LiveRoom(platform: 'iptv', roomId: 'two'));
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    expect(opened, ['one', 'two'], reason: 'the native player state must be created for the new room');
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('receiver home'), findsOneWidget);
    navigateProjectionRoom(LiveRoom(platform: 'iptv', roomId: 'three'));
    await tester.pumpAndSettle();
    expect(find.text('three'), findsOneWidget);
    expect(opened, ['one', 'two', 'three']);
  });
}

class _ReceiverRoom extends StatefulWidget {
  const new({required this.args, required this.opened});
  final LiveRoomArgs args;
  final List<String> opened;

  @override
  State<_ReceiverRoom> createState() => _ReceiverRoomState();
}

class _ReceiverRoomState extends State<_ReceiverRoom> {
  late final String playingRoom;

  @override
  void initState() {
    super.initState();
    playingRoom = widget.args.room.roomId;
    widget.opened.add(playingRoom);
    expect(widget.args.startFullscreen, isTrue);
  }

  @override
  Widget build(BuildContext context) => Text(playingRoom);
}
