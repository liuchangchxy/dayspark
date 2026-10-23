import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class WorkspaceSidebar extends StatelessWidget {
  const WorkspaceSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onInbox,
    required this.onToday,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onInbox;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.sidebar,
      child: SizedBox(
        width: 200,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          CupertinoIcons.calendar_badge_plus,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.appName,
                          style: AppTypography.body.copyWith(
                            color: AppColors.sidebarInk,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 4,
                        height: 4,
                        child: ColoredBox(color: AppColors.brandWarm),
                      ),
                    ],
                  ),
                ),
                _item(
                  context,
                  l.action,
                  CupertinoIcons.sun_max,
                  () => onSelected(0),
                  selectedIndex == 0,
                ),
                _item(
                  context,
                  l.calendar,
                  CupertinoIcons.calendar,
                  () => onSelected(1),
                  selectedIndex == 1,
                ),
                _item(
                  context,
                  l.todos,
                  CupertinoIcons.checkmark_rectangle,
                  () => onSelected(2),
                  selectedIndex == 2,
                ),
                const SizedBox(height: 24),
                _item(context, l.inbox, CupertinoIcons.tray, onInbox),
                _item(context, l.today, CupertinoIcons.sun_max, onToday),
                _item(
                  context,
                  l.manageTags,
                  CupertinoIcons.tag,
                  () => context.push('/tags'),
                ),
                const Spacer(),
                const Divider(color: AppColors.sidebarSelected),
                _item(
                  context,
                  l.settings,
                  CupertinoIcons.settings,
                  () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap, [
    bool selected = false,
  ]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          selected: selected,
          minTileHeight: 48,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          horizontalTitleGap: 10,
          leading: Icon(
            icon,
            size: 18,
            color: selected ? AppColors.sidebarInk : AppColors.sidebarMuted,
          ),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: selected ? AppColors.sidebarInk : AppColors.sidebarMuted,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
