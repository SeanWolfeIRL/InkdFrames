import 'package:flutter/material.dart';
import 'project_library_screen.dart';
import 'workspace_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InkdFrames'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            32,
            24,
            32 + MediaQuery.of(context).viewInsets.bottom,
          ),
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
                onPressed: () async {
                  final controller = TextEditingController();

                  final projectName = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Name your animation'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Bouncing Ball',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              final name = controller.text.trim();
                              if (name.isNotEmpty) {
                                Navigator.pop(context, name);
                              }
                            },
                            child: const Text('Create'),
                          ),
                        ],
                      );
                    },
                  );

                  if (projectName == null || !context.mounted) return;

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkspaceScreen(projectName: projectName),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text('Blank Animation'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const ProjectLibraryScreen(),
                    ),
                  );
                },
                child: const Text('Project Library'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
