import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('CalDAV Accounts'),
            subtitle: Text('Not yet implemented — Phase 3'),
          ),
          ListTile(
            leading: Icon(Icons.smart_toy_outlined),
            title: Text('AI Configuration'),
            subtitle: Text('Not yet implemented — Phase 6'),
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme and display options'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Calendar Todo v0.1.0'),
          ),
        ],
      ),
    );
  }
}
