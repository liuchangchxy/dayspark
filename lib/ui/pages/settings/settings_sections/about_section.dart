import 'package:flutter/material.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

class AboutSection extends StatefulWidget {
  const AboutSection({super.key, required this.version});

  final String version;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  bool _showLicenses = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final displayVersion = widget.version.isEmpty ? '0.34.0' : widget.version;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRows(
          children: [
            SettingsRow(
              label: l.versionLabel,
              subtitle: l.versionDesc,
              value: displayVersion,
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
              chevron: _showLicenses ? SettingsChevron.none : SettingsChevron.right,
              onTap: () => setState(() => _showLicenses = !_showLicenses),
            ),
          ],
        ),
        if (_showLicenses)
          Container(
            height: 380,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E5DF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: LicensePage(
              applicationName: 'DaySpark',
              applicationVersion: displayVersion,
            ),
          ),
      ],
    );
  }
}
