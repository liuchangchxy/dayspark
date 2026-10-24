import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _controller = TextEditingController();
  bool _copied = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The copied state belongs to the text that was copied. Editing afterwards
  /// means the clipboard no longer holds what is on screen, so the button
  /// stops claiming it does.
  void _onChanged(String _) {
    if (!_copied) return;
    setState(() => _copied = false);
  }

  Future<void> _copy() async {
    final l = AppLocalizations.of(context)!;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.feedbackCopied)));
  }

  Future<void> _openOnGitHub() async {
    final l = AppLocalizations.of(context)!;
    final text = _controller.text.trim();
    final body = text.isEmpty ? '' : Uri.encodeComponent(text);
    final uri = Uri.parse(
      'https://github.com/liuchangchxy/dayspark/issues/new?body=$body',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('feedback: launch failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.couldNotOpenLink)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return WorkspacePage(
      title: l.feedback,
      maxContentWidth: 640,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: InputDecoration(
              labelText: l.feedback,
              hintText: l.feedbackHint,
              alignLabelWithHint: true,
            ),
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.lg),
          // The primary button says what it does. "Submit" implied the text
          // left the device; it only ever reached the clipboard.
          FilledButton.icon(
            onPressed: _copied ? null : _copy,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: Icon(
              _copied
                  ? CupertinoIcons.checkmark_circle
                  : CupertinoIcons.doc_on_clipboard,
              size: 18,
            ),
            label: Text(_copied ? l.feedbackCopied : l.copyFeedback),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _openOnGitHub,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(CupertinoIcons.link, size: 18),
            label: Text(l.submitOnGitHub),
          ),
        ],
      ),
    );
  }
}
