import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/utils/version_compare.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _repo = 'liuchangchxy/dayspark';

  String _currentVersion = '';
  String _currentBuild = '';
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
    if (mounted) {
      setState(() {
        _currentVersion = info.version;
        _currentBuild = info.buildNumber;
      });
    }
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _error = null;
      _latestRelease = null;
    });
    try {
      final dio = Dio()..options.connectTimeout = const Duration(seconds: 10);
      final resp = await dio.get(
        'https://api.github.com/repos/$_repo/releases?per_page=1',
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'DaySpark/$_currentVersion',
          },
        ),
      );
      if (mounted) {
        final list = resp.data as List;
        setState(() {
          _latestRelease = list.isNotEmpty
              ? list.first as Map<String, dynamic>
              : null;
          _checking = false;
        });
      }
    } catch (e) {
      debugPrint('about: checkUpdate error: $e');
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _checking = false;
        });
      }
    }
  }

  bool get _hasUpdate {
    if (_latestRelease == null) return false;
    final tag = (_latestRelease!['tag_name'] as String?) ?? '';
    final latest = tag.replaceFirst(RegExp(r'^v'), '');
    return compareAppVersions(latest, _currentVersion) > 0;
  }

  String _friendlyError(dynamic e) {
    final l = AppLocalizations.of(context)!;
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return l.rateLimited(_repo);
      }
      if (e.type == DioExceptionType.connectionTimeout) {
        return l.connectionTimedOut;
      }
    }
    return l.updateCheckFailed(_repo);
  }

  /// A link that cannot open must say so; a silent tap reads as a dead row.
  Future<void> _openUrl(String url) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse(url);
      final launched =
          await canLaunchUrl(uri) &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        messenger.showSnackBar(SnackBar(content: Text(l.couldNotOpenLink)));
      }
    } catch (error) {
      debugPrint('about: launch failed: $error');
      messenger.showSnackBar(SnackBar(content: Text(l.couldNotOpenLink)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;

    return WorkspacePage(
      title: l.about,
      maxContentWidth: 640,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s6,
          AppSpacing.s4,
          AppSpacing.s8,
        ),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: ds.primary,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              alignment: Alignment.center,
              child: Text(
                'D',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: ds.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            'DaySpark',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: ds.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            '${l.currentVersion}: v$_currentVersion'
            '${_currentBuild.isEmpty ? '' : ' ($_currentBuild)'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: ds.ink3),
          ),
          const SizedBox(height: AppSpacing.s5),
          DsButton(
            label: l.checkUpdate,
            icon: CupertinoIcons.arrow_down_circle,
            expand: true,
            loading: _checking,
            onPressed: _checking ? null : _checkUpdate,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: ds.danger),
            ),
          ],
          if (_latestRelease != null) ...[
            const SizedBox(height: AppSpacing.s3),
            if (_hasUpdate) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: ds.tint(ds.primary),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: ds.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.arrow_down_circle_fill,
                          color: ds.primary,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Flexible(
                          child: Text(
                            l.newVersionAvailable(
                              _latestRelease!['tag_name'] as String? ?? '',
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ds.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Text(
                      _latestRelease!['body'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.55,
                        color: ds.ink2,
                      ),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: DsButton(
                        label: l.openUpdatePage,
                        small: true,
                        onPressed: () {
                          final htmlUrl =
                              _latestRelease!['html_url'] as String? ?? '';
                          if (htmlUrl.isNotEmpty) _openUrl(htmlUrl);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: ds.success,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    l.upToDate,
                    style: TextStyle(
                      fontSize: 13,
                      color: ds.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: AppSpacing.s6),
          const DsHairline(),
          const SizedBox(height: AppSpacing.s2),
          DsSettingRow(
            label: l.starOnGithub,
            onTap: () => _openUrl('https://github.com/$_repo'),
          ),
          DsSettingRow(
            label: l.reportIssue,
            onTap: () => context.push('/feedback'),
          ),
          DsSettingRow(
            label: l.thirdPartyLicenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'DaySpark',
              applicationVersion: _currentVersion,
            ),
          ),
        ],
      ),
    );
  }
}
