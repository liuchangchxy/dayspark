import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// Chrome shared by every pushed page.
///
/// On mobile it is a normal AppBar. On desktop the page lives inside
/// [WorkspaceScaffold], so it renders a compact workspace header instead — no
/// second navigation bar, no duplicated window frame. One widget, so a page
/// cannot accidentally look like a phone screen on the desktop.
class WorkspacePage extends StatelessWidget {
  const WorkspacePage({
    super.key,
    required this.title,
    required this.child,
    this.titleWidget,
    this.actions = const [],
    this.footer,
    this.maxContentWidth,
    this.scrollableHeader = false,
  });

  final String title;
  final Widget child;
  final Widget? titleWidget;
  final List<Widget> actions;

  /// Pinned to the bottom of the content pane (a save bar, an input).
  final Widget? footer;

  /// Caps the content column on wide screens. Null means full width.
  final double? maxContentWidth;

  final bool scrollableHeader;

  @override
  Widget build(BuildContext context) {
    final desktop = isWorkspaceLayout(context);
    if (!desktop) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => _leave(context)),
          title: titleWidget ?? Text(title),
          actions: actions,
        ),
        body: child,
        bottomNavigationBar: footer,
      );
    }

    final theme = Theme.of(context);
    // The header belongs to the content column, not to the window: a title
    // pinned to the far left above a centred 720px form reads as two unrelated
    // things stacked on top of each other.
    Widget header = SizedBox(
      height: 48,
      child: Padding(
        // Same horizontal inset as the content column below, so the title sits
        // on the same optical line as the first field of the form.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.back, size: 18),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => _leave(context),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child:
                  titleWidget ??
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ...actions,
          ],
        ),
      ),
    );
    if (maxContentWidth != null) {
      header = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth!),
          child: header,
        ),
      );
    }
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: maxContentWidth == null
                ? child
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth!),
                      child: child,
                    ),
                  ),
          ),
          if (footer != null) ...[
            Container(height: 1, color: context.semantic.separator),
            SafeArea(top: false, child: footer!),
          ],
        ],
      ),
    );
  }
}

/// Deep links and the desktop rail can land on a page with nothing beneath it,
/// so leaving has to fall back to Home instead of throwing.
void _leave(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    context.pop();
    return;
  }
  router?.go('/');
}

/// Primary action on a [WorkspacePage] — same shape in the mobile AppBar and
/// in the desktop header, so "Save" never moves between platforms.
class PageSaveButton extends StatelessWidget {
  const PageSaveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.saving = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: saving ? null : onPressed,
      style: TextButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        disabledBackgroundColor: theme.colorScheme.primary.withValues(
          alpha: 0.4,
        ),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
      ),
      child: saving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
