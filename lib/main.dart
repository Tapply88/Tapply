import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbService.init();
  runApp(const TapplyApp());
}

class TapplyApp extends StatelessWidget {
  const TapplyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tapply',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32), // hijau jamu
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
