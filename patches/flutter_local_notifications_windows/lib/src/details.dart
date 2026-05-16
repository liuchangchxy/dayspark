/// Stub Windows notification types — no FFI, avoids gen_snapshot AOT crash.

class WindowsInitializationSettings {
  const WindowsInitializationSettings({
    this.appName = 'App',
    this.appUserModelId = '',
    this.guid = '',
    this.iconPath,
  });

  final String appName;
  final String appUserModelId;
  final String guid;
  final String? iconPath;
}

class WindowsNotificationDetails {
  const WindowsNotificationDetails({
    this.actions = const <WindowsAction>[],
    this.progressBars = const <WindowsProgressBar>[],
    this.bindings = const <String, String>{},
  });

  final List<WindowsAction> actions;
  final List<WindowsProgressBar> progressBars;
  final Map<String, String> bindings;
}

enum WindowsActivationType { foreground, protocol, background }

enum WindowsNotificationBehavior { dismiss, pendingUpdate }

enum WindowsButtonStyle { success, critical }

enum WindowsActionPlacement { contextMenu }

class WindowsAction {
  const WindowsAction({
    required this.content,
    required this.arguments,
    this.activationType = WindowsActivationType.foreground,
    this.activationBehavior = WindowsNotificationBehavior.dismiss,
    this.placement,
    this.imageUri,
    this.inputId,
    this.buttonStyle,
    this.tooltip,
  });

  final String content;
  final String arguments;
  final WindowsActivationType activationType;
  final WindowsNotificationBehavior activationBehavior;
  final WindowsActionPlacement? placement;
  final Uri? imageUri;
  final String? inputId;
  final WindowsButtonStyle? buttonStyle;
  final String? tooltip;
}

class WindowsProgressBar {
  const WindowsProgressBar({
    this.title = '',
    this.value = 0.0,
    this.status = '',
  });

  final String title;
  final double value;
  final String status;

  Map<String, String> get data => {};
}
