import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_source.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

/// The comments of a video (A17.6 c15: one component for the player's
/// panel and the comments page): "热门" or "最新", the comments a page at a
/// time, "加载更多" at the end, and the A17.1 states (loading, empty, a
/// failure with its cause and "重试").
class TvVideoComments extends ConsumerStatefulWidget {
  /// Creates the comments of [oid] (the archive's aid).
  const new({required this.oid, this.autofocus = false, super.key});

  /// The archive.
  final int oid;

  /// Takes the focus (the first comment, else the sort buttons).
  final bool autofocus;

  @override
  ConsumerState<TvVideoComments> createState() => _TvVideoCommentsState();
}

class _TvVideoCommentsState extends ConsumerState<TvVideoComments> {
  bool _hot = true;
  final List<VodComment> _comments = [];
  String? _offset;
  bool _end = false;
  bool _busy = false;
  bool _loaded = false;
  Object? _error;
  final FocusNode _first = FocusNode(debugLabel: 'tv comment first');

  @override
  void initState() {
    super.initState();
    unawaited(_more());
  }

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_busy || _end) return;
    setState(() => _busy = true);
    final first = _comments.isEmpty;
    try {
      final page = await ref.read(videoSourceProvider).comments(widget.oid, hot: _hot, offset: _offset);
      if (!mounted) return;
      setState(() {
        if (first) _comments.addAll(page.pinned);
        _comments.addAll(page.comments);
        _offset = page.nextOffset;
        _end = page.isEnd || page.comments.isEmpty;
        _error = null;
      });
      if (first && widget.autofocus && _comments.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _first.requestFocus();
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loaded = true;
        });
      }
    }
  }

  void _sort(bool hot) {
    if (hot == _hot) return;
    setState(() {
      _hot = hot;
      _comments.clear();
      _offset = null;
      _end = false;
      _loaded = false;
    });
    unawaited(_more());
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final Widget body;
    if (_comments.isEmpty) {
      if (!_loaded || _busy) {
        body = const Center(child: CircularProgressIndicator());
      } else if (_error != null) {
        body = TvStatusView.failure(_error, onRetry: () => unawaited(_more()), autofocus: widget.autofocus);
      } else {
        body = TvStatusView(icon: TvIcons.noResults, title: i18n('tv_video_comments_empty'));
      }
    } else {
      body = ListView.separated(
        itemCount: _comments.length + (_end ? 0 : 1),
        separatorBuilder: (_, _) => SizedBox(height: scale.px(8)),
        itemBuilder: (context, index) {
          if (index == _comments.length) {
            return Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-comments-more'),
                label: i18n(_busy ? 'tv_video_loading' : 'tv_video_more'),
                onTap: _busy ? null : () => unawaited(_more()),
              ),
            );
          }
          return _CommentRow(
            key: ValueKey('tv-comment-$index'),
            comment: _comments[index],
            focusNode: index == 0 ? _first : null,
          );
        },
      );
    }
    return Column(
      key: const ValueKey('tv-video-comments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TvButton(
              key: const ValueKey('tv-comments-hot'),
              label: i18n('tv_video_comments_hot'),
              selected: _hot,
              autofocus: widget.autofocus && _comments.isEmpty,
              onTap: () => _sort(true),
            ),
            SizedBox(width: scale.px(12)),
            TvButton(
              key: const ValueKey('tv-comments-new'),
              label: i18n('tv_video_comments_new'),
              selected: !_hot,
              onTap: () => _sort(false),
            ),
          ],
        ),
        SizedBox(height: scale.px(16)),
        Expanded(child: body),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const new({required this.comment, this.focusNode, super.key});

  final VodComment comment;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return TvFocusable(
      focusNode: focusNode,
      zoom: false,
      builder: (context, focused) => Container(
        padding: EdgeInsets.all(scale.px(16)),
        decoration: BoxDecoration(
          color: focused ? palette.highest : palette.card,
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommonAvatar(avatarUrl: comment.user.face, fallbackName: comment.user.name, radius: scale.pxText(20)),
            SizedBox(width: scale.px(16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [comment.user.name, if (comment.pinned) i18n('tv_video_comment_pinned')].join(' · '),
                    style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.textSecondary),
                  ),
                  SizedBox(height: scale.px(4)),
                  Text(
                    comment.text,
                    maxLines: focused ? 12 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: scale.font(TvTextSize.body, color: palette.text, height: 1.5),
                  ),
                  SizedBox(height: scale.px(4)),
                  Text(
                    [
                      i18n('tv_video_comment_likes', args: {'count': videoCount(comment.likes)}),
                      if (comment.replyCount > 0)
                        i18n('tv_video_comment_replies', args: {'count': videoCount(comment.replyCount)}),
                      if (comment.location.isNotEmpty) comment.location,
                    ].join(' · '),
                    style: scale.font(TvTextSize.small, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
