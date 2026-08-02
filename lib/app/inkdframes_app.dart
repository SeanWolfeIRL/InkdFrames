import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/workspace_screen.dart';

class InkdFramesApp extends StatelessWidget {
  const InkdFramesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkdFrames',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.cyanAccent,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1B24),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurpleAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
      ),
      home: const HomeScreen(),
      routes: {WorkspaceScreen.routeName: (context) => const WorkspaceScreen()},
    );
  }
}
