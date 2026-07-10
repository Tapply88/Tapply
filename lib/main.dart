import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/db_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await DbService.init();
  runApp(const TapplyApp());
}

class TapplyApp extends StatelessWidget {
  const TapplyApp({super.key});

  static const backgroundColor = Color(0xFFD6CFC6);
  static const fontColor = Color(0xFF623609);

  @override
  Widget build(BuildContext context) {
    final textTheme = Typography.material2021().black.apply(
          bodyColor: fontColor,
          displayColor: fontColor,
        );

    return MaterialApp(
      title: 'Tapply',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: fontColor,
          surface: backgroundColor,
        ),
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: backgroundColor,
          foregroundColor: fontColor,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: backgroundColor,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: backgroundColor,
          indicatorColor: fontColor.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: fontColor, fontSize: 12),
          ),
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: fontColor),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
