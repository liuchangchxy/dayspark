import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'settings_sections/about_section.dart';
import 'settings_sections/ai_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/import_export_section.dart';
import 'settings_sections/notifications_section.dart';

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
      Future.microtask(
        () => NotificationsSection.loadSystemAlarmSetting(ref),
      );
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
      body: ListView(
        children: [
          const AppearanceSection(),
          const Divider(),
          const ImportExportSection(),
          const Divider(),
          const AiSection(),
          const NotificationsSection(),
          AboutSection(version: _cachedVersion ?? ''),
        ],
      ),
    );
  }
}
