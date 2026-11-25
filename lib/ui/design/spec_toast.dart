import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/ui/design/a2.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

const Color _toastInk = Color(0xFF1B1B1A);
const Color _toastPaper = Color(0xFFFFFFFF);
const double _toastMaxWidth = 560;

/// Desktop clears the bottom edge; mobile clears the 56px tab bar the same
/// way the undo bar does (spec `.m-undo` / toast bottom 118).
const double _toastBottomGapDesktop = 84;
const double _toastBottomGapMobile = 118;

void showSpecToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(milliseconds: 2200),
  bool danger = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  final bottomGap = isWorkspaceLayout(context)
      ? _toastBottomGapDesktop
      : _toastBottomGapMobile;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        elevation: 0,
        backgroundColor: const Color(0x00000000),
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.only(left: 24, right: 24, bottom: bottomGap),
        content: _SpecToastBody(
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          danger: danger,
        ),
      ),
    );
}

void hideSpecToast(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}

class _SpecToastBody extends StatelessWidget {
  const _SpecToastBody({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.danger = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.min(_toastMaxWidth, screenWidth * 0.8);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: danger ? SpecTokens.red : _toastInk,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x29000000),
                blurRadius: 22,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _toastPaper,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 12),
                FocusableTap(
                  onTap: () {
                    hideSpecToast(context);
                    onAction!();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: _toastPaper,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: _toastPaper,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
