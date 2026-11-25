import 'package:live_core/live_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Shared phone, desktop and TV presentation of platform-published information.
/// Missing data is shown as unavailable, independently of the room signature.
class BroadcastInformation extends StatelessWidget {
  /// Creates the information sections. Styles may follow a TV's scaled theme.
  const new({required this.information, this.style, this.selectable = true, super.key});

  /// Null until a platform metadata response or sync event has arrived.
  final LiveBroadcastInfo? information;

  /// Optional platform-specific text scale/style.
  final TextStyle? style;

  /// TV informational text must not introduce hidden selection focus stops.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final info = information;
    final body = style ?? Theme.of(context).textTheme.bodyMedium;
    Widget section(String title, String text, String key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: body?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (selectable)
            SelectableText(text, key: ValueKey(key), style: body)
          else
            Text(text, key: ValueKey(key), style: body),
        ],
      ),
    );
    if (info == null) {
      return section(i18n('room_broadcast_information'), i18n('room_broadcast_unavailable'), 'broadcast-unavailable');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section(
          i18n('room_broadcast_preview'),
          info.preview?.text ?? i18n('room_broadcast_no_preview'),
          'broadcast-preview',
        ),
        if (info.dynamics.isNotEmpty)
          section(i18n('room_broadcast_dynamics'), info.dynamics.join('\n\n'), 'broadcast-dynamics'),
      ],
    );
  }
}
