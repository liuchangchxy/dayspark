import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/l10n/app_localizations.dart';

void main() {
  test('occurrence history navigation is localized in English and Chinese',
      () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final chinese = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(english.earlierThirtyDays, 'Earlier 30 days');
    expect(english.newerOccurrences, 'Newer');
    expect(chinese.earlierThirtyDays, '更早 30 天');
    expect(chinese.newerOccurrences, '较新的实例');
  });
}
