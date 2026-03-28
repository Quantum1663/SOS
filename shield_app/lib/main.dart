import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shield_app/features/sos/presentation/sos_home_screen.dart';
import 'package:shield_app/services/shortcut_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ShortcutService.initialize();

  runApp(
    const ProviderScope(
      child: ShieldApp(),
    ),
  );
}

class ShieldApp extends StatelessWidget {
  const ShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SHIELD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
      ),
      home: const SosHomeScreen(),
    );
  }
}
