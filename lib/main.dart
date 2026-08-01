import 'package:flutter/material.dart';

void main() {
  runApp(const InkdFramesApp());
}

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
      home: const InkdFramesHome(),
    );
  }
}

class InkdFramesHome extends StatelessWidget {
  const InkdFramesHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InkdFrames'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turn your Galaxy Ultra into a portable animation studio.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const Text(
                'Start with a blank animation or import a memory to sketch frame by frame.',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {},
                child: const Text('Import a Memory'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text('Blank Animation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
