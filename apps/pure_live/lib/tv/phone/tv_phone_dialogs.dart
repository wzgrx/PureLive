import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/phone_bridge.dart';
import 'package:pure_live/tv/phone/tv_phone_server.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_qr_panel.dart';

/// The TV's [PhoneBridge] (A17.9 c15), for the pages below [child].
class TvPhoneBridge extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The pages.
  final Widget child;

  @override
  Widget build(BuildContext context) => PhoneBridge(input: showTvPhoneInput, view: showTvPhoneView, child: child);
}

/// Fills [request] on a phone: the code of a one-off page on this network;
/// the values when the phone sends them, null when cancelled (Back).
Future<Map<String, String>?> showTvPhoneInput(BuildContext context, PhoneInputRequest request) =>
    showTvDialog<Map<String, String>>(
      context,
      builder: (context) => _ServerDialog(
        title: request.title,
        start: () => TvPhoneServer.start(form: request),
        panelTitle: i18n('tv_phone_input_title'),
        steps: [i18n('tv_phone_step_scan'), i18n('tv_phone_step_fill'), i18n('tv_phone_step_done')],
      ),
    );

/// Shows [text] on a phone: the code of a one-off page on this network
/// (a log is easier to read there).
Future<void> showTvPhoneView(BuildContext context, {required String title, required String text}) => showTvDialog<void>(
  context,
  builder: (context) => _ServerDialog(
    title: title,
    start: () => TvPhoneServer.start(text: text, title: title),
    panelTitle: i18n('tv_phone_view_title'),
    steps: [i18n('tv_phone_step_scan'), i18n('tv_phone_step_read')],
  ),
);

/// A web address for a phone (A17.9 c14, c18: the project page, the MPV
/// manual): most televisions have no browser, so the code opens it there.
Future<void> showTvLink(BuildContext context, {required String title, required String url}) => showTvDialog<void>(
  context,
  builder: (context) => TvDialog(
    key: const ValueKey('tv-link-dialog'),
    title: title,
    width: 1400,
    actions: [
      TvButton(
        key: const ValueKey('tv-link-close'),
        label: i18n('close'),
        autofocus: true,
        onTap: () => Navigator.pop(context),
      ),
    ],
    child: TvQrPanel(data: url, title: i18n('tv_link_title'), steps: [i18n('tv_link_step')], address: url),
  ),
);

class _ServerDialog extends StatefulWidget {
  const new({required this.title, required this.start, required this.panelTitle, required this.steps});

  final String title;
  final Future<TvPhoneServer> Function() start;
  final String panelTitle;
  final List<String> steps;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  TvPhoneServer? _server;
  Object? _error;
  Timer? _poll;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final server = await widget.start();
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() => _server = server);
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        if (server.opened != _opened && mounted) setState(() => _opened = server.opened);
      });
      if (server.form != null) {
        final values = await server.submitted;
        if (mounted) Navigator.pop(context, values);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_server?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return TvDialog(
      key: const ValueKey('tv-phone-dialog'),
      title: widget.title,
      width: 1400,
      actions: [
        TvButton(
          key: const ValueKey('tv-phone-close'),
          label: i18n('cancel'),
          autofocus: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
      child: _error != null
          ? TvDialogText(i18n('tv_phone_failed'))
          : server == null
          ? TvDialogText(i18n('tv_phone_starting'))
          : TvQrPanel(
              data: server.url,
              title: widget.panelTitle,
              status: i18n(_opened ? 'tv_phone_opened' : 'tv_phone_running'),
              steps: widget.steps,
              address: server.url,
            ),
    );
  }
}
