/// Compares the version strings the app publishes (semver, optionally with a
/// prerelease suffix and an optional build number).
///
/// [PackageInfo.version] on its own drops the build number and keeps an
/// arbitrary prerelease string, so a plain `int.parse` comparison read
/// "0.29.0-beta" as a newer release than "0.29.0" and reported no update on a
/// channel that had moved on. This follows semver 2.0 precedence: numeric
/// core, then prerelease (a prerelease sorts *before* its release), then the
/// `+build` metadata is ignored because semver says it carries no precedence.
int compareAppVersions(String a, String b) {
  final left = _ParsedVersion.parse(a);
  final right = _ParsedVersion.parse(b);
  if (left == null || right == null) return 0;

  final core = _compareNumeric(left.core, right.core);
  if (core != 0) return core;

  if (left.prerelease == null && right.prerelease == null) return 0;
  if (left.prerelease == null) return 1;
  if (right.prerelease == null) return -1;

  final lParts = left.prerelease!.split('.');
  final rParts = right.prerelease!.split('.');
  for (var i = 0; i < lParts.length || i < rParts.length; i++) {
    if (i >= lParts.length) return -1;
    if (i >= rParts.length) return 1;
    final lNum = int.tryParse(lParts[i]);
    final rNum = int.tryParse(rParts[i]);
    if (lNum != null && rNum != null) {
      if (lNum != rNum) return lNum - rNum;
    } else if (lNum != null) {
      return -1;
    } else if (rNum != null) {
      return 1;
    } else {
      final cmp = lParts[i].compareTo(rParts[i]);
      if (cmp != 0) return cmp;
    }
  }
  return 0;
}

int _compareNumeric(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final va = i < a.length ? a[i] : 0;
    final vb = i < b.length ? b[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

class _ParsedVersion {
  const _ParsedVersion(this.core, this.prerelease);

  final List<int> core;
  final String? prerelease;

  static _ParsedVersion? parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    // Build metadata ("+29") has no ordering meaning.
    final plus = value.indexOf('+');
    if (plus >= 0) value = value.substring(0, plus);
    final dash = value.indexOf('-');
    final corePart = dash >= 0 ? value.substring(0, dash) : value;
    final prerelease = dash >= 0 ? value.substring(dash + 1) : null;
    final core = <int>[];
    for (final part in corePart.split('.')) {
      final parsed = int.tryParse(part);
      if (parsed == null) return null;
      core.add(parsed);
    }
    if (core.isEmpty) return null;
    return _ParsedVersion(core, prerelease);
  }
}
