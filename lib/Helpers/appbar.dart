import 'package:flutter/material.dart';
import 'package:subject_tools/main.dart' show getThemeModeNotifier;

class Appbartop extends StatelessWidget implements PreferredSizeWidget {
  const Appbartop({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _toggleTheme(BuildContext context) {
    try {
      final ValueNotifier<ThemeMode> themeModeNotifier = getThemeModeNotifier();
      themeModeNotifier.value = themeModeNotifier.value == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (e) {
      debugPrint('Error toggling theme: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling theme: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return AppBar(
      title: const Center(child: Text(
        'Subject Tools',
        style: TextStyle(fontWeight: FontWeight.bold),
      )),
      backgroundColor: isDarkMode ? Colors.blue.shade700 : Colors.blue.shade600,
      foregroundColor: Colors.white,
      elevation: 2,
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Center(
            child: Tooltip(
              message: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              child: IconButton(
                onPressed: () => _toggleTheme(context),
                icon: Icon(
                  isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}