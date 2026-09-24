import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/domain/providers/todos_ui_prefs_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class TodosSection extends ConsumerWidget {
  const TodosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: const Icon(CupertinoIcons.eye_slash),
          title: Text(l.hideCompleted),
          subtitle: Text(l.hideCompletedDesc),
          value: ref.watch(hideCompletedProvider).valueOrNull ?? false,
          onChanged: (v) => ref.read(setHideCompletedProvider)(v),
        ),
      ],
    );
  }
}
