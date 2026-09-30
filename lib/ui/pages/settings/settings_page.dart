import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/centered_content.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';
import 'settings_sections/todos_section.dart';
import 'package:dayspark/core/utils/platform_target.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/widgets/settings_group.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static bool _loaded = false;
  static String? _cachedVersion;

  @override
  void initState() {
    super.initState();
    // Load persisted settings once on first build
    if (!_loaded) {
      _loaded = true;
      Future.microtask(() => NotificationsSection.loadSystemAlarmSetting(ref));
      PackageInfo.fromPlatform().then((i) {
        _cachedVersion = 'DaySpark v${i.version}';
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.settings),
      ),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            // No header over these two: their first row already says what
            // they are, and a header would just repeat it.
            for (final group in <(String?, Widget)>[
              (null, const AppearanceSection()),
              (null, const TodosSection()),
              (l.data, const ImportExportSection()),
              (l.account, const AccountSection()),
              (l.advancedFeatures, const AiSection()),
              // The notification rows are platform-gated; without them the
              // section would render an empty card under a bare label.
              if (hasNotificationSettings)
                (l.notifications, const NotificationsSection()),
            ])
              SettingsGroup(
                title: group.$1,
                child: group.$2,
              ),
            _AdvancedGroup(version: _cachedVersion ?? ''),
          ],
        ),
      ),
    );
  }
}

/// Notification rows exist only where the platform can actually schedule
/// them (web cannot).
bool get hasNotificationSettings => isAndroid || isIOS || isWindows;

/// Collapsed tail of the settings page: the advanced/about material stays
/// behind an expansion so the everyday groups are all that is on screen.
class _AdvancedGroup extends StatelessWidget {
  const _AdvancedGroup({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsGroup(
      child: ExpansionTile(
        leading: const Icon(CupertinoIcons.gear),
        title: Text(l.advancedSettings),
        initiallyExpanded: false,
        children: [AboutSection(version: version)],
      ),
    );
  }
}
