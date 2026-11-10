import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// Chrome shared by every pushed page.
///
/// Mobile: a 54px paper top bar. Desktop: the page sits inside
/// [WorkspaceScaffold] and renders the same 54px bar without a second window
/// frame. One widget so "Save" never moves between platforms.
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
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? footer;
  final double? maxContentWidth;
  final bool scrollableHeader;

  @override
  Widget build(BuildContext context) {
    final desktop = isWorkspaceLayout(context);
    final canPop = GoRouter.maybeOf(context)?.canPop() ?? false;
    final showBack = canPop;

    final content = maxContentWidth == null
        ? child
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth!),
              child: child,
            ),
          );

    if (!desktop) {
      return Scaffold(
        backgroundColor: context.ds.bg,
        appBar: DsTopBar(
          title: titleWidget == null ? title : '',
          leading: showBack
              ? DsIconButton(
                  icon: CupertinoIcons.back,
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).backButtonTooltip,
                  onPressed: () => _leave(context),
                )
              : null,
          actions: actions,
        ),
        body: titleWidget == null
            ? child
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      0,
                      AppSpacing.s4,
                      AppSpacing.s3,
                    ),
                    child: titleWidget,
                  ),
                  Expanded(child: child),
                ],
              ),
        bottomNavigationBar: footer == null
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: context.ds.surface,
                  border: Border(
                    top: BorderSide(color: context.ds.lineSoft),
                  ),
                ),
                child: SafeArea(top: false, child: footer!),
              ),
      );
    }

    final header = DsMainBar(
      title: title,
      actions: [
        if (showBack)
          DsIconButton(
            icon: CupertinoIcons.back,
            size: 18,
            compact: true,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => _leave(context),
          ),
        if (actions.isNotEmpty) ...actions,
      ],
      contextLabel: subtitle,
    );

    return Scaffold(
      backgroundColor: context.ds.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: content),
          if (footer != null)
            Container(
              decoration: BoxDecoration(
                color: context.ds.surface,
                border: Border(top: BorderSide(color: context.ds.lineSoft)),
              ),
              child: SafeArea(top: false, child: footer!),
            ),
        ],
      ),
    );
  }
}

void _leave(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    context.pop();
    return;
  }
  router?.go('/');
}

/// Primary action on a [WorkspacePage] — same shape in the mobile top bar and
/// the desktop header.
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
    return DsButton(
      label: label,
      tone: DsButtonTone.primary,
      small: true,
      loading: saving,
      onPressed: onPressed,
    );
  }
}
