import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsRow(
      label: l.appName,
      value: version,
      chevron: SettingsChevron.right,
      onTap: () => context.push('/about'),
    );
  }
}
