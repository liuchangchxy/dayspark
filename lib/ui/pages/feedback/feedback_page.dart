import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_toast.dart';
import 'package:dayspark/ui/pages/settings/settings_ui.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';

/// Opens the GitHub issue composer. A seam so a widget test can prove the
/// inline failure state without depending on a browser.
typedef FeedbackLinkOpener = Future<bool> Function(Uri uri);

final feedbackLinkOpenerProvider = Provider<FeedbackLinkOpener>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key});

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  final _controller = TextEditingController();
  bool _copied = false;
  bool _linkError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The copied state belongs to the text that was copied. Editing afterwards
  /// means the clipboard no longer holds what is on screen, so the button
  /// stops claiming it does. Every change also refreshes whether there is
  /// anything to copy at all.
  void _onChanged(String _) {
    if (_copied) {
      setState(() => _copied = false);
    } else {
      setState(() {});
    }
  }

  Future<void> _copy() async {
    final l = AppLocalizations.of(context)!;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      _copied = true;
      _linkError = false;
    });
    showSpecToast(context, l.feedbackCopied);
  }

  Future<void> _openOnGitHub() async {
    final text = _controller.text.trim();
    final body = text.isEmpty ? '' : Uri.encodeComponent(text);
    final uri = Uri.parse(
      'https://github.com/liuchangchxy/dayspark/issues/new?body=$body',
    );
    var opened = false;
    try {
      opened = await ref.read(feedbackLinkOpenerProvider)(uri);
    } catch (error) {
      debugPrint('feedback: launch failed: $error');
      opened = false;
    }
    if (!mounted) return;
    setState(() => _linkError = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = _controller.text;
    final hasText = text.trim().isNotEmpty;
    return WorkspacePage(
      title: l.feedback,
      maxContentWidth: 640,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s4,
          AppSpacing.s4,
          AppSpacing.s6,
        ),
        children: [
          DsField(
            label: l.feedbackWriteLabel,
            child: DsTextField(
              controller: _controller,
              hint: l.feedbackPlaceholder,
              maxLines: 8,
              onChanged: _onChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.feedbackCharCount(text.runes.length),
                  style: AppTypography.caption,
                ),
              ),
              Text(
                hasText ? l.feedbackMetaReady : l.feedbackMetaEmpty,
                style: AppTypography.caption,
              ),
            ],
          ),
          if (_linkError)
            InlineAlert(
              title: l.feedbackLinkErrorTitle,
              message: l.feedbackLinkErrorBody,
              isRed: true,
            ),
          const SizedBox(height: AppSpacing.s4),
          // The primary button says what it does. "Submit" implied the text
          // left the device; it only ever reached the clipboard.
          DsButton(
            label: _copied ? l.feedbackCopied : l.copyFeedback,
            icon: _copied
                ? CupertinoIcons.checkmark_circle
                : CupertinoIcons.doc_on_clipboard,
            expand: true,
            // Empty text has nothing to copy; copied text stays copyable so a
            // second copy does not become a dead button.
            onPressed: hasText ? _copy : null,
          ),
          const SizedBox(height: AppSpacing.s2),
          DsButton(
            label: l.submitOnGitHub,
            icon: CupertinoIcons.link,
            tone: DsButtonTone.secondary,
            expand: true,
            onPressed: _openOnGitHub,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            l.feedbackNoSilentSubmit,
            style: AppTypography.caption.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
