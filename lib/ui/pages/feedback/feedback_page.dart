import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dayspark/l10n/app_localizations.dart';

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.feedback),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: l.feedback,
              hintText: l.feedbackHint,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isEmpty) return;
              Clipboard.setData(ClipboardData(text: text));
              setState(() => _copied = true);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l.feedbackCopied)));
            },
            icon: Icon(
              _copied ? CupertinoIcons.checkmark_circle : CupertinoIcons.doc_on_clipboard,
              size: 18,
            ),
            label: Text(l.feedbackSubmit),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              final text = _controller.text.trim();
              final body = text.isEmpty ? '' : Uri.encodeComponent(text);
              launchUrl(
                Uri.parse(
                  'https://github.com/liuchangchxy/dayspark/issues/new?body=$body',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(CupertinoIcons.link, size: 18),
            label: const Text('GitHub'),
          ),
        ],
      ),
    );
  }
}
