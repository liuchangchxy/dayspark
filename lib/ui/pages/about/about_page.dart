import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _repo = 'liuchangchxy/dayspark';

  String _currentVersion = '';
  bool _checking = false;
  Map<String, dynamic>? _latestRelease;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _currentVersion = info.version);
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _error = null;
      _latestRelease = null;
    });
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://api.github.com/repos/$_repo/releases?per_page=1',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      if (mounted) {
        final list = resp.data as List;
        setState(() {
          _latestRelease = list.isNotEmpty ? list.first as Map<String, dynamic> : null;
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _checking = false;
        });
      }
    }
  }

  bool get _hasUpdate {
    if (_latestRelease == null) return false;
    final tag = (_latestRelease!['tag_name'] as String?) ?? '';
    final latest = tag.replaceFirst(RegExp(r'^v'), '');
    return _compareVersions(latest, _currentVersion) > 0;
  }

  int _compareVersions(String a, String b) {
    final pa = a.split('.').map(int.parse).toList();
    final pb = b.split('.').map(int.parse).toList();
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.about),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            CupertinoIcons.calendar_badge_plus,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'DaySpark',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l.currentVersion}: v$_currentVersion',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _checking ? null : _checkUpdate,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(CupertinoIcons.arrow_down_circle, size: 18),
              label: Text(l.checkUpdate),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
          if (_latestRelease != null) ...[
            const SizedBox(height: 16),
            if (_hasUpdate) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.arrow_down_circle_fill,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            l.newVersionAvailable(
                              _latestRelease!['tag_name'] as String? ?? '',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _latestRelease!['body'] as String? ?? '',
                      style: theme.textTheme.bodySmall,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () {
                          final htmlUrl =
                              _latestRelease!['html_url'] as String? ?? '';
                          if (htmlUrl.isNotEmpty) _openUrl(htmlUrl);
                        },
                        child: Text(l.downloadUpdate),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.green.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.upToDate,
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(CupertinoIcons.star),
            title: Text(l.starOnGithub),
            onTap: () => _openUrl('https://github.com/$_repo'),
            trailing: const Icon(CupertinoIcons.link, size: 16),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.exclamationmark_triangle),
            title: Text(l.reportIssue),
            onTap: () => context.push('/feedback'),
            trailing: const Icon(CupertinoIcons.right_chevron, size: 16),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.doc_text),
            title: Text(l.thirdPartyLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'DaySpark',
              applicationVersion: _currentVersion,
            ),
            trailing: const Icon(CupertinoIcons.right_chevron, size: 16),
          ),
        ],
      ),
    );
  }
}
