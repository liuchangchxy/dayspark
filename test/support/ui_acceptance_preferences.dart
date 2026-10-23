import 'package:shared_preferences/shared_preferences.dart';

void initializeAcceptancePreferences() {
  SharedPreferences.setMockInitialValues({
    'app_locale': const String.fromEnvironment('QA_LOCALE', defaultValue: 'zh'),
    'theme_mode': const String.fromEnvironment(
      'QA_THEME',
      defaultValue: 'light',
    ),
    'calendar_view_mode': 'week',
  });
}
