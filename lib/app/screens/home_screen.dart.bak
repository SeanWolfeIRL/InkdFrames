import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
                onPressed: () async {
                  final mediaType = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return SimpleDialog(
                        title: const Text('Import a Memory'),
                        children: [
                          SimpleDialogOption(
                            onPressed: () {
                              Navigator.pop(context, 'image');
                            },
                            child: const ListTile(
                              leading: Icon(Icons.image_outlined),
                              title: Text('Import Image'),
                              subtitle: Text('JPG, JPEG or PNG'),
                            ),
                          ),
                          SimpleDialogOption(
                            onPressed: () {
                              Navigator.pop(context, 'video');
                            },
                            child: const ListTile(
                              leading: Icon(Icons.videocam_outlined),
                              title: Text('Import Video'),
                              subtitle: Text('Video reference'),
                            ),
                          ),
                        ],
                      );
                    },
                  );

                  if (mediaType == null || !context.mounted) return;

                  final pickedFile = await FilePicker.pickFile(
                    type: mediaType == 'image'
                        ? FileType.image
                        : FileType.video,
                  );

                  if (pickedFile == null || !context.mounted) {
                    return;
                  }

                  if (pickedFile.path == null) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not access that file.'),
                      ),
                    );
                    return;
                  }

                  final controller = TextEditingController(
                    text: pickedFile.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
                  );

                  final screenSize = MediaQuery.sizeOf(context);
                  var isPortrait = screenSize.height > screenSize.width;

                  final result =
                      await showDialog<({String name, bool portrait})>(
                        context: context,
                        builder: (context) {
                          return StatefulBuilder(
                            builder: (context, setDialogState) {
                              return AlertDialog(
                                title: Text(
                                  mediaType == 'image'
                                      ? 'Create from image'
                                      : 'Create from video',
                                ),
                                content: SizedBox(
                                  width: 360,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextField(
                                        controller: controller,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Animation name',
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      const Text(
                                        'Canvas orientation',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      SegmentedButton<bool>(
                                        segments: const [
                                          ButtonSegment<bool>(
                                            value: false,
                                            icon: Icon(Icons.crop_landscape),
                                            label: Text('Landscape'),
                                          ),
                                          ButtonSegment<bool>(
                                            value: true,
                                            icon: Icon(Icons.crop_portrait),
                                            label: Text('Portrait'),
                                          ),
                                        ],
                                        selected: {isPortrait},
                                        onSelectionChanged: (selection) {
                                          setDialogState(() {
                                            isPortrait = selection.first;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        isPortrait
                                            ? '1080 × 1920'
                                            : '1920 × 1080',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
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

                                      if (name.isEmpty) return;

                                      Navigator.pop(context, (
                                        name: name,
                                        portrait: isPortrait,
                                      ));
                                    },
                                    child: const Text('Create'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );

                  controller.dispose();

                  if (result == null || !context.mounted) return;

                  final referenceDirectory = Directory(
                    '/data/user/0/com.inkdframes.app/files/reference_media',
                  );

                  if (!await referenceDirectory.exists()) {
                    await referenceDirectory.create(recursive: true);
                  }

                  final extension = pickedFile.name.contains('.')
                      ? '.${pickedFile.name.split('.').last}'
                      : '';

                  final storedPath =
                      '${referenceDirectory.path}/'
                      '${DateTime.now().microsecondsSinceEpoch}$extension';

                  await File(pickedFile.path!).copy(storedPath);

                  if (!context.mounted) return;

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkspaceScreen(
                        projectName: result.name,
                        initialCanvasWidth: result.portrait ? 1080 : 1920,
                        initialCanvasHeight: result.portrait ? 1920 : 1080,
                        initialReferenceMediaPath: storedPath,
                        initialReferenceMediaType: mediaType,
                      ),
                    ),
                  );
                },
                child: const Text('Import a Memory'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final controller = TextEditingController();

                  final screenSize = MediaQuery.sizeOf(context);
                  var isPortrait = screenSize.height > screenSize.width;

                  final result =
                      await showDialog<({String name, bool portrait})>(
                        context: context,
                        builder: (context) {
                          return StatefulBuilder(
                            builder: (context, setDialogState) {
                              return AlertDialog(
                                title: const Text('Create animation'),
                                content: SizedBox(
                                  width: 360,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextField(
                                        controller: controller,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Animation name',
                                          hintText: 'e.g. Bouncing Ball',
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      const Text(
                                        'Canvas orientation',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      SegmentedButton<bool>(
                                        segments: const [
                                          ButtonSegment<bool>(
                                            value: false,
                                            icon: Icon(Icons.crop_landscape),
                                            label: Text('Landscape'),
                                          ),
                                          ButtonSegment<bool>(
                                            value: true,
                                            icon: Icon(Icons.crop_portrait),
                                            label: Text('Portrait'),
                                          ),
                                        ],
                                        selected: {isPortrait},
                                        onSelectionChanged: (selection) {
                                          setDialogState(() {
                                            isPortrait = selection.first;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        isPortrait
                                            ? '1080 × 1920'
                                            : '1920 × 1080',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
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

                                      if (name.isEmpty) {
                                        return;
                                      }

                                      Navigator.pop(context, (
                                        name: name,
                                        portrait: isPortrait,
                                      ));
                                    },
                                    child: const Text('Create'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );

                  controller.dispose();

                  if (result == null || !context.mounted) return;

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkspaceScreen(
                        projectName: result.name,
                        initialCanvasWidth: result.portrait ? 1080 : 1920,
                        initialCanvasHeight: result.portrait ? 1920 : 1080,
                      ),
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
