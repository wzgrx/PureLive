import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';

/// A page of the TV settings (A17.9 c3, c4): the title, then [child] in the
/// TV's safe area (48 and 28 of the 960 × 540 panel); the first focusable
/// of [child] has the focus when it opens, and Back goes back onto the row
/// that opened it.
class TvSettingsScaffold extends StatefulWidget {
  /// Creates the page.
  const new({required this.title, required this.child, this.pageKey, this.contentHasHeader = false, super.key});

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// The scaffold's key (`tv-settings-page-<name>`).
  final Key? pageKey;

  /// The shared page supplies a header through [SettingsPageHeaderScope].
  final bool contentHasHeader;

  @override
  State<TvSettingsScaffold> createState() => _TvSettingsScaffoldState();
}

class _TvSettingsScaffoldState extends State<TvSettingsScaffold> {
  final FocusScopeNode _body = FocusScopeNode(debugLabel: 'tv settings page', skipTraversal: true);
  bool _focusedInitially = false;
  bool _focusPending = false;
  bool _currentRoute = true;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_followFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route visibility, so loading under a dialog does not
    // permanently abandon initial focus when the dialog is dismissed.
    _currentRoute = ModalRoute.isCurrentOf(context) ?? true;
    _focusFirst();
  }

  void _focusFirst() {
    if (!mounted || _focusedInitially || _focusPending || !_currentRoute) return;
    _focusPending = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(() {
        _focusPending = false;
        if (!mounted || _focusedInitially || !_currentRoute) return;
        final primary = FocusManager.instance.primaryFocus;
        if (_body.hasFocus && primary is! FocusScopeNode) {
          _focusedInitially = true;
          return;
        }
        for (final node in _body.traversalDescendants) {
          if (node is! FocusScopeNode &&
              node.context != null &&
              node.context!.findAncestorWidgetOfExactType<TvPageHeader>() == null) {
            _focusedInitially = true;
            node.requestFocus();
            return;
          }
        }
        // A shared page may load for many frames before attaching targets.
        // Wait on its next actual frame; never request frames while idle.
        _focusFirst();
      }),
    );
  }

  void _followFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (_currentRoute &&
        _focusedInitially &&
        primary is FocusScopeNode &&
        (_body.hasFocus || _body.ancestors.contains(primary))) {
      // Loading can replace a previously focused row (IPTV inserts its
      // overview above the settings). A scope is not a usable target.
      // Recover only after that target disappeared, never from another
      // control, a header action, or a dialog covering this route.
      _focusedInitially = false;
      _focusFirst();
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    if (!_body.hasFocus) return;
    final focused = primary?.context;
    if (focused == null || Scrollable.maybeOf(focused) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focused.mounted || !_currentRoute || FocusManager.instance.primaryFocus != primary) return;
      final scrollable = Scrollable.maybeOf(focused);
      if (scrollable == null) return;
      var target = focused;
      focused.visitAncestorElements((element) {
        if (element.widget is! SettingsRow) return true;
        final box = element.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          final extent = scrollable.position.axis == Axis.vertical ? box.size.height : box.size.width;
          // Reveal the row's label and full focus frame as well as the
          // slider/counter inside it. An oversized row keeps its focused part.
          if (extent <= scrollable.position.viewportDimension) target = element;
        }
        return false;
      });
      final object = target.findRenderObject();
      if (object == null || !object.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) return;
      // A loading page can retain an offset below its new first row. The
      // end-only policy never scrolls back to a focused row above the clip.
      final start = viewport.getOffsetToReveal(object, 0, axis: scrollable.position.axis).offset;
      final policy = start < scrollable.position.pixels
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
      Scrollable.ensureVisible(target, alignmentPolicy: policy).ignore();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_followFocus);
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return Scaffold(
      key: widget.pageKey,
      backgroundColor: TvTheme.pageOf(context),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: scale.px(96), vertical: scale.px(56)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.contentHasHeader) ...[
              TvPageHeader(title: widget.title, subtitle: i18n('tv_menu_settings')),
              SizedBox(height: scale.px(16)),
            ],
            Expanded(
              child: FocusScope(
                node: _body,
                child: Theme(
                  data: Theme.of(context).copyWith(scaffoldBackgroundColor: OnVideoColors.clear),
                  child: TvSettingsStyle(
                    child: SettingsPageHeaderScope(builder: _header, child: widget.child),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _header(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<Widget> actions = const [],
    PreferredSizeWidget? bottom,
  }) {
    final scale = TvScale.of(context);
    return PreferredSize(
      preferredSize: Size.fromHeight(scale.pxText(76) + (bottom?.preferredSize.height ?? 0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvPageHeader(title: title, subtitle: subtitle ?? i18n('tv_menu_settings'), actions: actions),
          SizedBox(height: scale.px(16)),
          ?bottom,
        ],
      ),
    );
  }
}

/// One page of the TV settings (A17.9 c2–c6): the phone's rows of
/// [section] (the catalogue, so the words, icons and order are the phone's)
/// in their TV look, one column at most 720 wide in the middle.
class TvSettingsSectionPage extends StatelessWidget {
  /// Creates the page.
  const new({required this.section, super.key});

  /// The page shown.
  final SettingsSection section;

  @override
  Widget build(BuildContext context) => TvSettingsScaffold(
    pageKey: ValueKey('tv-settings-page-${section.name}'),
    title: i18n(section.titleKey),
    child: SettingsSectionView(section: section),
  );
}

/// A TV settings page of its own content, one column at most 720 wide in
/// the middle, scrolling.
class TvSettingsColumn extends StatelessWidget {
  /// Creates the column.
  const new({required this.children, super.key});

  /// The rows and groups.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: TvScale.of(context).px(1440)),
      child: ListView(children: children),
    ),
  );
}

/// "弹幕" of the TV settings (A17.9 c13, D1 A): the phone's danmaku settings
/// (`DanmakuSettingsContent`, the same as the room's panel) with the chat
/// list group; no floating-window group, a TV has no floating windows.
class TvDanmakuSettingsPage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context) => TvSettingsScaffold(
    pageKey: const ValueKey('tv-settings-page-danmaku'),
    title: i18n(SettingsSection.danmaku.titleKey),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: TvScale.of(context).px(1440)),
        child: DanmakuSettingsContent(
          hint: i18n('danmaku_settings_live_hint'),
          extra: [PanelGroupTitle(i18n('danmaku_list')), const ChatListSettings()],
        ),
      ),
    ),
  );
}
