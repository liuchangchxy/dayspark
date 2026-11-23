import 'package:flutter/material.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsRows(
      children: [
        SettingsRow(
          label: l.versionLabel,
          subtitle: l.versionDesc,
          value: version.isEmpty ? '0.35.0' : version,
        ),
        SettingsRow(
          label: l.dataLocation,
          subtitle: l.dataDesc,
          value: l.dataLocationDesc,
        ),
        SettingsRow(
          label: l.license,
          subtitle: l.licenseDesc,
          value: l.viewLicense,
          chevron: SettingsChevron.right,
          onTap: () => showLicensePage(context: context),
        ),
      ],
    );
  }
}
