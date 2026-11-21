import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// How long an undo stays offered. The completion window in the lists is the
/// same five seconds, so the bar and the row disappear together.
const Duration kUndoBarDuration = Duration(seconds: 5);

const ValueKey<String> kUndoBarKey = ValueKey('undo-bar');

/// Frozen spec geometry: desktop `.undo-bar` is a centered compact pill 84px
/// above the bottom edge; mobile `.m-undo` is inset 12px and sits above the
/// 56px tab bar.
const double _desktopBottom = 84;
const double _desktopWidth = 360;
const double _mobileBottom = 68;
const double _mobileEdge = 12;

/// Shows the one-line undo bar for the current message.
///
/// This is deliberately built on [ScaffoldMessenger] so it shares the app's
/// single snackbar surface, but it opts out of two defaults that broke the
/// Android acceptance run:
///
/// * Flutter 3.41 defaults `SnackBar.persist` to true whenever an
///   [SnackBarAction] is present, so an action snackbar never times out. The
///   bar sets `persist: false` and an explicit duration.
/// * The bar is lifted off the bottom chrome with a margin, so it no longer
///   covers the mobile tab bar or a page's bottom action bar. A non-null
///   margin also makes the snackbar's [Dismissible] defer hit testing to the
///   bar itself, so taps outside it reach the widgets underneath.
///
/// The user can dismiss it by swiping down or by tapping the message; tapping
/// "undo" hides the bar and runs [onUndo].
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndoBar(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  final desktop = isWorkspaceLayout(context);
  final width = MediaQuery.sizeOf(context).width;
  final side = desktop
      ? math.max(_mobileEdge, (width - _desktopWidth) / 2)
      : _mobileEdge;
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    SnackBar(
      key: kUndoBarKey,
      persist: false,
      duration: kUndoBarDuration,
      dismissDirection: DismissDirection.down,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.fromLTRB(
        side,
        0,
        side,
        desktop ? _desktopBottom : _mobileBottom,
      ),
      content: _UndoBarContent(
        key: const ValueKey('undo-bar-content'),
        message: message,
        undoLabel: undoLabel,
        onUndo: onUndo,
      ),
    ),
  );
}

class _UndoBarContent extends StatelessWidget {
  const _UndoBarContent({
    super.key,
    required this.message,
    required this.undoLabel,
    required this.onUndo,
  });

  final String message;
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style;
    void dismiss() =>
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              onDismiss: dismiss,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: dismiss,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              dismiss();
              onUndo();
            },
            style: TextButton.styleFrom(
              foregroundColor: textStyle.color,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: textStyle.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: textStyle.color,
              ),
            ),
            child: Text(undoLabel),
          ),
        ],
      ),
    );
  }
}
