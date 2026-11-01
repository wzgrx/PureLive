import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/toolbox/toolbox_actions.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/phone_bridge.dart';
import 'package:pure_live/shared/rooms/archive_navigation.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';

/// Link playback on the TV (A17.5 c12, pure_live_TV `LinkPlayPage`): a field
/// typed with the remote or sent from the existing phone form; "播放" opens the room the link
/// points to in the TV room. The phone's toolbox resolves it (the same
/// parser, platforms and 12-second limit, share codes too); while it works
/// and when it fails the line under the field says so.
class TvLinkPane extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<TvLinkPane> createState() => _TvLinkPaneState();
}

class _TvLinkPaneState extends ConsumerState<TvLinkPane> {
  late final ToolboxController _toolbox = ToolboxController(
    links: ref.read(toolboxLinksProvider),
    siteOf: ref.read(toolboxSiteProvider),
    openRoom: ({required liveRoom}) async {
      await openTvRoom(liveRoom);
    },
    notify: (key) {
      if (mounted) setState(() => _error = i18n(key));
    },
  )..addListener(_changed);
  String _link = '';
  String? _error;
  bool _phonePending = false;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _toolbox
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final link = _link.trim();
    if (link.isEmpty || _toolbox.isBusy) return;
    setState(() => _error = null);
    await _toolbox.jump(link);
  }

  void _submit(String value) {
    final link = value.trim();
    if (_toolbox.isBusy) return;
    setState(() {
      _link = link;
      _error = null;
    });
    unawaited(_play());
  }

  Future<void> _phoneInput(PhoneBridge bridge) async {
    if (_phonePending || _toolbox.isBusy) return;
    _phonePending = true;
    Map<String, String>? values;
    try {
      values = await bridge.input(
        context,
        PhoneInputRequest(
          title: i18n('tv_menu_link'),
          fields: [
            PhoneInputField(
              key: 'link',
              label: i18n('tv_menu_link'),
              initial: _link,
              hint: i18n('tv_link_hint'),
              multiline: true,
            ),
          ],
        ),
      );
    } finally {
      _phonePending = false;
    }
    if (!mounted) return;
    if (values?['link'] case final link? when link.trim().isNotEmpty) _submit(link);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final busy = _toolbox.isBusy;
    final bridge = PhoneBridge.maybeOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(scale.px(48), scale.px(28), scale.px(48), scale.px(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvPageHeader(title: i18n('tv_menu_link')),
          SizedBox(height: scale.px(24)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scale.pxText(900)),
            child: TvInputField(
              key: const ValueKey('tv-link-field'),
              text: _link,
              hint: i18n('tv_link_hint'),
              title: i18n('tv_menu_link'),
              icon: AppIcons.link,
              onSubmitted: _submit,
            ),
          ),
          SizedBox(height: scale.px(12)),
          Text(
            busy ? i18n('tv_link_parsing') : (_error ?? i18n('tv_link_desc')),
            key: const ValueKey('tv-link-status'),
            style: scale.font(TvTextSize.body, color: _error != null && !busy ? palette.danger : palette.textSecondary),
          ),
          SizedBox(height: scale.px(20)),
          Wrap(
            spacing: scale.px(12),
            runSpacing: scale.px(12),
            children: [
              TvButton(
                key: const ValueKey('tv-link-huya-archives'),
                label: i18n('huya_replay_title'),
                onTap: () => unawaited(openHuyaArchives(context)),
              ),
              TvButton(
                key: const ValueKey('tv-link-douyu-vod'),
                label: i18n('douyu_vod_title'),
                onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kDouyuVod)),
              ),
              TvButton(
                key: const ValueKey('tv-link-play'),
                label: i18n('tv_link_play'),
                kind: TvButtonKind.primary,
                onTap: _link.trim().isEmpty || busy ? null : () => unawaited(_play()),
              ),
              if (bridge != null)
                TvButton(
                  key: const ValueKey('tv-link-phone'),
                  icon: TvIcons.phoneInput,
                  label: i18n('tv_search_phone'),
                  onTap: busy ? null : () => unawaited(_phoneInput(bridge)),
                ),
              if (busy) ...[
                TvButton(key: const ValueKey('tv-link-cancel'), label: i18n('cancel'), onTap: _toolbox.cancel),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
