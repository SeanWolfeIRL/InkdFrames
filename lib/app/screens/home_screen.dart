import 'package:flutter/material.dart';

import 'workspace_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                onPressed: () {
                  Navigator.of(context).pushNamed(WorkspaceScreen.routeName);
                },
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
