import 'package:flutter/material.dart';
import 'package:subject_tools/home.dart';

final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeModeNotifier,
      builder: (BuildContext context, ThemeMode themeMode, Widget? child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFFAFAFA),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              elevation: 2,
              centerTitle: false,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF121212),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              elevation: 2,
              centerTitle: false,
            ),
          ),
          home: const Home(),
          navigatorObservers: <NavigatorObserver>[_RouteObserver()],
        );
      },
    );
  }
}

// Export theme notifier for use in other parts of the app
ValueNotifier<ThemeMode> getThemeModeNotifier() => _themeModeNotifier;

class _RouteObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('Route popped: ${route.settings.name}');
    super.didPop(route, previousRoute);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('Route pushed: ${route.settings.name}');
    super.didPush(route, previousRoute);
  }
}