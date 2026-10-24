import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/core/utils/version_compare.dart';

/// DaySpark ships every v0.x as a prerelease, so the comparison has to know
/// that "0.29.0-beta" is *older* than "0.29.0" — otherwise About tells a
/// beta user they are up to date against the release they are waiting for.
void main() {
  test('a prerelease sorts before its release', () {
    expect(compareAppVersions('0.29.0-beta', '0.29.0'), lessThan(0));
    expect(compareAppVersions('0.29.0', '0.29.0-beta'), greaterThan(0));
    expect(compareAppVersions('0.29.0-rc.1', '0.29.0'), lessThan(0));
  });

  test('the numeric core still decides first', () {
    expect(compareAppVersions('0.29.0', '0.28.9'), greaterThan(0));
    expect(compareAppVersions('0.9.0', '0.10.0'), lessThan(0));
    expect(compareAppVersions('1.0.0', '0.99.0'), greaterThan(0));
  });

  test('prerelease identifiers follow semver, not string order', () {
    expect(
      compareAppVersions('0.29.0-beta.2', '0.29.0-beta.10'),
      lessThan(0),
      reason: 'numeric identifiers compare numerically',
    );
    expect(compareAppVersions('0.29.0-alpha', '0.29.0-beta'), lessThan(0));
  });

  test('build metadata carries no precedence', () {
    expect(compareAppVersions('0.29.0+29', '0.29.0+28'), 0);
    expect(compareAppVersions('v0.29.0', '0.29.0'), 0);
  });

  test('an unparseable side compares as equal rather than pretending', () {
    expect(compareAppVersions('not-a-version', '0.29.0'), 0);
  });
}
