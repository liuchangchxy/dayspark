import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/l10n/app_localizations.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(CupertinoIcons.info),
      title: Text(l.about),
      subtitle: Text(version),
      onTap: () => context.push('/about'),
    );
  }
}
