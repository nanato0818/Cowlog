import 'package:flutter/material.dart';

import 'screens/root_screen.dart';
import 'state/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.initialize();
  runApp(CowlogApp(store: store));
}

class CowlogApp extends StatelessWidget {
  const CowlogApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cowlog',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176d54)),
      useMaterial3: true,
    ),
    home: RootScreen(store: store),
  );
}
