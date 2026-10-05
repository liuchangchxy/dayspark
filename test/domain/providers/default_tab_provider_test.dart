import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaultTabProvider', () {
    test('defaults to AppTab.action when no preference is saved', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial state before load finishes
      expect(container.read(defaultTabProvider), AppTab.action);

      // Let SharedPreferences load complete
      await pumpEventQueue();
      expect(container.read(defaultTabProvider), AppTab.action);
    });

    test('preserves existing calendar preference', () async {
      SharedPreferences.setMockInitialValues({'default_tab': 'calendar'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Trigger notifier creation
      container.read(defaultTabProvider.notifier);
      await pumpEventQueue();
      expect(container.read(defaultTabProvider), AppTab.calendar);
    });

    test('preserves existing todos preference', () async {
      SharedPreferences.setMockInitialValues({'default_tab': 'todos'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Trigger notifier creation
      container.read(defaultTabProvider.notifier);
      await pumpEventQueue();
      expect(container.read(defaultTabProvider), AppTab.todos);
    });

    test('setDefaultTab updates state and persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await pumpEventQueue();
      expect(container.read(defaultTabProvider), AppTab.action);

      await container.read(defaultTabProvider.notifier).setDefaultTab(AppTab.calendar);
      expect(container.read(defaultTabProvider), AppTab.calendar);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('default_tab'), 'calendar');

      await container.read(defaultTabProvider.notifier).setDefaultTab(AppTab.action);
      expect(container.read(defaultTabProvider), AppTab.action);
      expect(prefs.getString('default_tab'), 'action');
    });
  });
}
