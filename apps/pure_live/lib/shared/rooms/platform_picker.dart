import 'dart:async';
import 'dart:math' as math;

import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// How much of a phone's height "all platforms" opens at when its list is
/// longer (A09.2 v4-phone-picker: the top at about 29%; A09.12 c3).
const double platformPickerOpenHeight = 0.71;

/// "All platforms" (U.4b c2): every platform of the tabs with its logo and
/// name, the current one ticked; a tap switches to it and closes the panel;
/// "平台显示" opens the settings that hide and order them. The same content
/// rises from the bottom on phones and sits on the right on wide screens.
class PlatformPicker extends StatelessWidget {
  /// Creates the picker of [ids] with [current] selected.
  const new({required this.ids, required this.current, super.key});

  static int _columns(double width) =>
      GridColumns.count(width: width, minItemWidth: 84, spacing: 8, padding: 12, min: 3, max: 6);

  static double _tileHeight(TextScaler textScaler) => 76 + textScaler.scale(13) * 1.4;

  /// The height the picker of [count] platforms needs as a bottom panel
  /// [width] wide, with the panel's handle.
  static double heightOf(int count, {required double width, required TextScaler textScaler}) {
    final rows = (count / _columns(width)).ceil();
    final grid = rows * _tileHeight(textScaler) + math.max(0, rows - 1) * 4 + 16;
    // The handle, the header and its line, the one-line hint.
    return kMinInteractiveDimension + kMinInteractiveDimension + 5 + textScaler.scale(13) * 1.5 + 8 + grid;
  }

  /// The platforms of the tabs.
  final List<String> ids;

  /// The index of the platform shown.
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The panel's frame (U.1d): a line under the header once scrolled.
    return PanelFrame(
      key: const ValueKey('popular-platform-picker'),
      expand: false,
      header: PanelHeader(
        title: i18n('popular_all_platforms'),
        closeTooltip: i18n('close'),
        actions: [
          TextButton.icon(
            key: const ValueKey('popular-platform-settings'),
            onPressed: () {
              Navigator.pop(context);
              unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas));
            },
            icon: const Icon(AppIcons.platformSettings, size: 18),
            label: Text(i18n('platform_display')),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              withoutOrphan(i18n('popular_all_platforms_hint')),
              key: const ValueKey('popular-platform-hint'),
              style: context.textStyles.t13.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = _columns(constraints.maxWidth);
                return GridView.builder(
                  // A docked bottom panel moves with this list's drags.
                  primary: true,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 4,
                    mainAxisExtent: _tileHeight(MediaQuery.textScalerOf(context)),
                  ),
                  itemCount: ids.length,
                  itemBuilder: (context, index) => _PlatformTile(
                    id: ids[index],
                    selected: index == current,
                    onTap: () => Navigator.pop(context, index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const new({required this.id, required this.selected, required this.onTap});

  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('popular-platform-$id'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          selected: selected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(9), child: PlatformLogo(id, size: 36)),
                      if (selected)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            key: const ValueKey('popular-platform-selected'),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.secondaryContainer, width: 2),
                            ),
                            child: Icon(AppIcons.selected, size: 12, color: scheme.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // A long Latin name (SHOWROOM, YouTube Live) narrows a
                // little rather than losing its end to an ellipsis.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    platformName(id, fallback: id.toUpperCase()),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: context.textStyles.t13.copyWith(
                      height: 1.4,
                      color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
