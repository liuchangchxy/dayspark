import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/ui/design/ds.dart';

/// The one empty-state shape: icon, title, one line of explanation, action.
///
/// Every page's blank state goes through this so they stay recognisably the
/// same family while each says something different (DESIGN 空状态模板).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  /// Optional content under the action, e.g. a short list of suggestions.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final hasHint = hint != null && hint!.isNotEmpty;
    final trailing = action == null && extra == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action != null) action!,
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.s3),
                extra!,
              ],
            ],
          );
    return Center(
      child: SingleChildScrollView(
        child: DsEmpty(
          icon: icon,
          title: hasHint ? title : null,
          message: hasHint ? hint! : title,
          action: trailing,
        ),
      ),
    );
  }
}
