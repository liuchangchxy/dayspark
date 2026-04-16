/// App-wide constants.
abstract final class AppConstants {
  static const String appName = 'Calendar Todo';

  // Sync defaults
  static const Duration defaultSyncInterval = Duration(seconds: 30);
  static const Duration syncPollingInterval = Duration(seconds: 10);

  // UI spacing (base unit: 4px, matching DESIGN.md)
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 24;
  static const double spacingXxl = 32;

  // Border radius
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;

  // Animation
  static const Duration animationDuration = Duration(milliseconds: 200);
}
