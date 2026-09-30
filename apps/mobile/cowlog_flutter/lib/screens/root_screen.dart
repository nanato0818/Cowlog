import 'package:flutter/material.dart';

import '../state/app_store.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(store: widget.store),
      MapScreen(store: widget.store),
      SettingsScreen(store: widget.store),
    ];
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => Scaffold(
        body: pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: '優先一覧',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: '地図',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '接続設定',
            ),
          ],
        ),
      ),
    );
  }
}
